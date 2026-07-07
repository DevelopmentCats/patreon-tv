// Unit tests for the pairing state machine and session sealing.
// Run with `npm test` (vitest). The KV namespace is mocked in-memory,
// including TTL-based expiry.

import { beforeEach, describe, expect, it, vi } from "vitest";
import {
  claimPairingSession,
  completePairing,
  createPairing,
  formatCode,
  generateCode,
  issueOAuthNonce,
  normalizeCode,
  pairingStatus,
  readPairing,
  verifyOAuthNonce,
  type PairingEnv,
} from "./pairing";
import { importSessionKey, isSealed, openSession, sealSession } from "./sessionCrypto";
import { rateLimit } from "./rateLimit";

// 32 zero bytes, base64 — fine for tests.
const TEST_KEY = Buffer.alloc(32, 7).toString("base64");

interface StoredValue {
  value: string;
  expiresAt: number | null;
}

/** Minimal in-memory KVNamespace supporting get/put with expirationTtl. */
function makeKV() {
  const store = new Map<string, StoredValue>();
  const kv = {
    async get(key: string): Promise<string | null> {
      const entry = store.get(key);
      if (!entry) return null;
      if (entry.expiresAt !== null && Date.now() >= entry.expiresAt) {
        store.delete(key);
        return null;
      }
      return entry.value;
    },
    async put(key: string, value: string, options?: { expirationTtl?: number }): Promise<void> {
      store.set(key, {
        value,
        expiresAt: options?.expirationTtl ? Date.now() + options.expirationTtl * 1000 : null,
      });
    },
    _store: store,
  };
  return kv as unknown as KVNamespace & { _store: Map<string, StoredValue> };
}

function makeEnv(overrides: Partial<PairingEnv> = {}): PairingEnv & { PAIRING: ReturnType<typeof makeKV> } {
  return {
    PAIRING: makeKV(),
    PAIRING_SESSION_KEY: TEST_KEY,
    ...overrides,
  } as PairingEnv & { PAIRING: ReturnType<typeof makeKV> };
}

describe("code generation", () => {
  it("generates 8-char codes from the unambiguous alphabet", () => {
    for (let i = 0; i < 50; i++) {
      const code = generateCode();
      expect(code).toMatch(/^[ABCDEFGHJKLMNPQRSTUVWXYZ23456789]{8}$/);
    }
  });

  it("normalizes and formats codes", () => {
    expect(normalizeCode("ab-cd 12!34")).toBe("ABCD1234");
    expect(formatCode("abcd1234")).toBe("ABCD-1234");
  });
});

describe("pairing lifecycle", () => {
  let env: ReturnType<typeof makeEnv>;

  beforeEach(() => {
    env = makeEnv();
    vi.useRealTimers();
  });

  it("create → complete → claim returns the session exactly once", async () => {
    const record = await createPairing(env);
    expect(record.status).toBe("pending");

    const completed = await completePairing(env, record.code, "  my-session  ");
    expect(completed?.status).toBe("complete");

    const claim = await claimPairingSession(env, record.code);
    expect(claim.status).toBe("complete");
    expect(claim.session_id).toBe("my-session");

    // Second claim: already consumed.
    const second = await claimPairingSession(env, record.code);
    expect(second.status).toBe("claimed");
    expect(second.session_id).toBeUndefined();
  });

  it("seals the session at rest — never plaintext in KV", async () => {
    const record = await createPairing(env);
    await completePairing(env, record.code, "super-secret-session");

    const raw = await env.PAIRING.get(`pair:${record.code}`);
    expect(raw).not.toBeNull();
    expect(raw).not.toContain("super-secret-session");
    const stored = JSON.parse(raw!) as { session_id: string };
    expect(isSealed(stored.session_id)).toBe(true);
  });

  it("stores plaintext only when no key is configured (local dev)", async () => {
    const devEnv = makeEnv({ PAIRING_SESSION_KEY: undefined });
    const record = await createPairing(devEnv);
    await completePairing(devEnv, record.code, "dev-session");

    const claim = await claimPairingSession(devEnv, record.code);
    expect(claim.session_id).toBe("dev-session");
  });

  it("polling before completion reports pending without consuming", async () => {
    const record = await createPairing(env);
    expect(await pairingStatus(env, record.code)).toBe("pending");
    const claim = await claimPairingSession(env, record.code);
    expect(claim.status).toBe("pending");
  });

  it("rejects completion of unknown codes", async () => {
    expect(await completePairing(env, "AAAA2222", "s")).toBeNull();
  });

  it("rejects completion of expired codes and does not resurrect them", async () => {
    vi.useFakeTimers();
    const record = await createPairing(env);
    vi.advanceTimersByTime(11 * 60 * 1000); // past the 10-minute TTL

    expect(await readPairing(env, record.code)).toBeNull();
    expect(await completePairing(env, record.code, "late-session")).toBeNull();
    expect((await claimPairingSession(env, record.code)).status).toBe("missing");
    vi.useRealTimers();
  });

  it("rejects completion of already-claimed codes", async () => {
    const record = await createPairing(env);
    await completePairing(env, record.code, "s1");
    await claimPairingSession(env, record.code);

    expect(await completePairing(env, record.code, "s2")).toBeNull();
  });

  it("treats sealed sessions as dead when the key is missing", async () => {
    const record = await createPairing(env);
    await completePairing(env, record.code, "sealed-session");

    const keylessEnv = { ...env, PAIRING_SESSION_KEY: undefined } as PairingEnv;
    const claim = await claimPairingSession(keylessEnv, record.code);
    expect(claim.status).toBe("missing");
    expect(claim.session_id).toBeUndefined();
  });
});

describe("OAuth nonce", () => {
  it("issues a nonce for pending records and verifies it", async () => {
    const env = makeEnv();
    const record = await createPairing(env);

    const nonce = await issueOAuthNonce(env, record.code);
    expect(nonce).toMatch(/^[0-9a-f]{32}$/);

    expect(await verifyOAuthNonce(env, record.code, nonce!)).toBe(true);
    expect(await verifyOAuthNonce(env, record.code, "wrong")).toBe(false);
    expect(await verifyOAuthNonce(env, record.code, "")).toBe(false);
  });

  it("refuses to issue a nonce for completed or unknown codes", async () => {
    const env = makeEnv();
    const record = await createPairing(env);
    await completePairing(env, record.code, "s");

    expect(await issueOAuthNonce(env, record.code)).toBeNull();
    expect(await issueOAuthNonce(env, "AAAA2222")).toBeNull();
  });
});

describe("sessionCrypto", () => {
  it("round-trips a session through seal/open", async () => {
    const key = await importSessionKey(TEST_KEY);
    const sealed = await sealSession("session-value", key);
    expect(isSealed(sealed)).toBe(true);
    expect(sealed).not.toContain("session-value");
    expect(await openSession(sealed, key)).toBe("session-value");
  });

  it("fails to open with the wrong key", async () => {
    const key = await importSessionKey(TEST_KEY);
    const otherKey = await importSessionKey(Buffer.alloc(32, 9).toString("base64"));
    const sealed = await sealSession("session-value", key);
    expect(await openSession(sealed, otherKey)).toBeNull();
  });

  it("rejects keys that are not 32 bytes", async () => {
    await expect(importSessionKey(Buffer.alloc(16, 1).toString("base64"))).rejects.toThrow();
  });
});

describe("rate limiter", () => {
  it("allows up to the limit then rejects within the window", async () => {
    const kv = makeKV();
    for (let i = 0; i < 3; i++) {
      const result = await rateLimit(kv, "test", "1.2.3.4", 3, 60);
      expect(result.allowed).toBe(true);
    }
    const rejected = await rateLimit(kv, "test", "1.2.3.4", 3, 60);
    expect(rejected.allowed).toBe(false);
  });

  it("tracks identifiers independently", async () => {
    const kv = makeKV();
    await rateLimit(kv, "test", "a", 1, 60);
    const other = await rateLimit(kv, "test", "b", 1, 60);
    expect(other.allowed).toBe(true);
  });
});
