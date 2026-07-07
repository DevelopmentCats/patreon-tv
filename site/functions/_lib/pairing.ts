import { importSessionKey, isSealed, openSession, sealSession } from "./sessionCrypto";

export interface PairingEnv {
  PAIRING: KVNamespace;
  PATREON_CLIENT_ID?: string;
  PATREON_CLIENT_SECRET?: string;
  /** OAuth redirect, e.g. https://patreontv.com/api/pairing/oauth/callback */
  PATREON_REDIRECT_URI?: string;
  /** Public site origin for link URLs, e.g. https://patreontv.com */
  PAIRING_PUBLIC_ORIGIN?: string;
  /**
   * 32-byte base64 key for sealing session cookies at rest in KV
   * (openssl rand -base64 32). REQUIRED in production — without it the raw
   * Patreon session (account-takeover material) sits in KV in plaintext.
   * Local dev without the key falls back to plaintext storage.
   */
  PAIRING_SESSION_KEY?: string;
}

export interface PairingRecord {
  code: string;
  status: "pending" | "complete" | "claimed";
  created_at: string;
  expires_at: string;
  /** Sealed (AES-GCM) when PAIRING_SESSION_KEY is configured. */
  session_id?: string;
  /** Random nonce binding the OAuth round-trip to this record (CSRF). */
  oauth_nonce?: string;
}

const CODE_ALPHABET = "ABCDEFGHJKLMNPQRSTUVWXYZ23456789";
const TTL_SECONDS = 10 * 60;
/** KV minimum TTL. */
const MIN_TTL_SECONDS = 60;

export function publicOrigin(env: PairingEnv, request: Request): string {
  return (env.PAIRING_PUBLIC_ORIGIN ?? new URL(request.url).origin).replace(/\/$/, "");
}

export function pairingKey(code: string): string {
  return `pair:${normalizeCode(code)}`;
}

export function normalizeCode(raw: string): string {
  return raw.replace(/[^A-Za-z0-9]/g, "").toUpperCase();
}

export function formatCode(raw: string): string {
  const normalized = normalizeCode(raw);
  if (normalized.length <= 4) return normalized;
  return `${normalized.slice(0, 4)}-${normalized.slice(4, 8)}`;
}

export function generateCode(): string {
  // 8 chars from a 32-symbol alphabet = 40 bits. 256 % 32 === 0, so the
  // modulo introduces no bias.
  const bytes = crypto.getRandomValues(new Uint8Array(8));
  let code = "";
  for (const byte of bytes) {
    code += CODE_ALPHABET[byte % CODE_ALPHABET.length];
  }
  return code.slice(0, 8);
}

function isExpired(record: PairingRecord, now = Date.now()): boolean {
  return now > Date.parse(record.expires_at);
}

/** Seconds of validity left, floored at the KV minimum so writes never fail. */
function remainingTtl(record: PairingRecord, now = Date.now()): number {
  const remaining = Math.ceil((Date.parse(record.expires_at) - now) / 1000);
  return Math.max(remaining, MIN_TTL_SECONDS);
}

async function sessionKey(env: PairingEnv): Promise<CryptoKey | null> {
  if (!env.PAIRING_SESSION_KEY) return null;
  return importSessionKey(env.PAIRING_SESSION_KEY);
}

export async function createPairing(env: PairingEnv): Promise<PairingRecord> {
  const now = Date.now();
  const record: PairingRecord = {
    code: generateCode(),
    status: "pending",
    created_at: new Date(now).toISOString(),
    expires_at: new Date(now + TTL_SECONDS * 1000).toISOString(),
  };
  await env.PAIRING.put(pairingKey(record.code), JSON.stringify(record), {
    expirationTtl: TTL_SECONDS,
  });
  return record;
}

/** Returns null for missing OR expired codes — expired records are dead. */
export async function readPairing(env: PairingEnv, code: string): Promise<PairingRecord | null> {
  const raw = await env.PAIRING.get(pairingKey(code));
  if (!raw) return null;
  const record = JSON.parse(raw) as PairingRecord;
  if (isExpired(record)) return null;
  return record;
}

/**
 * Attaches a fresh OAuth nonce to a pending record and returns it. The nonce
 * travels through the OAuth `state` parameter alongside the code, so a forged
 * callback that only knows the pairing code cannot complete the pairing.
 */
export async function issueOAuthNonce(env: PairingEnv, code: string): Promise<string | null> {
  const record = await readPairing(env, code);
  if (!record || record.status !== "pending") return null;

  const bytes = crypto.getRandomValues(new Uint8Array(16));
  const nonce = Array.from(bytes, (b) => b.toString(16).padStart(2, "0")).join("");

  const updated: PairingRecord = { ...record, oauth_nonce: nonce };
  await env.PAIRING.put(pairingKey(code), JSON.stringify(updated), {
    expirationTtl: remainingTtl(record),
  });
  return nonce;
}

export async function verifyOAuthNonce(
  env: PairingEnv,
  code: string,
  nonce: string,
): Promise<boolean> {
  if (!nonce) return false;
  const record = await readPairing(env, code);
  return Boolean(record?.oauth_nonce) && record?.oauth_nonce === nonce;
}

/**
 * Stores the session against a live pending code. Rejects expired/claimed
 * codes and preserves the record's original TTL (a completion must not extend
 * the pairing window). The session is sealed at rest when a key is configured.
 */
export async function completePairing(
  env: PairingEnv,
  code: string,
  sessionID: string,
): Promise<PairingRecord | null> {
  const record = await readPairing(env, code);
  if (!record || record.status === "claimed") return null;

  const key = await sessionKey(env);
  const trimmed = sessionID.trim();
  const stored = key ? await sealSession(trimmed, key) : trimmed;

  const updated: PairingRecord = {
    ...record,
    status: "complete",
    session_id: stored,
  };
  await env.PAIRING.put(pairingKey(code), JSON.stringify(updated), {
    expirationTtl: remainingTtl(record),
  });
  return updated;
}

/** Non-consuming status check (safe for GET polling). */
export async function pairingStatus(
  env: PairingEnv,
  code: string,
): Promise<"pending" | "complete" | "claimed" | "missing"> {
  const record = await readPairing(env, code);
  if (!record) return "missing";
  return record.status;
}

/**
 * TV claims the session: returns it once, then marks the record claimed.
 *
 * NOTE: KV has no compare-and-swap and is eventually consistent, so
 * "returns once" is best-effort — two concurrent claims racing the `claimed`
 * write can both receive the session. The pairing window is short (≤10 min),
 * the code is single-device, and the claim endpoint is rate-limited, which
 * bounds the practical exposure. Exact once-only semantics would need a
 * Durable Object.
 */
export async function claimPairingSession(
  env: PairingEnv,
  code: string,
): Promise<{ status: "pending" | "complete" | "claimed" | "missing"; session_id?: string }> {
  const record = await readPairing(env, code);
  if (!record) return { status: "missing" };
  if (record.status === "claimed") return { status: "claimed" };
  if (record.status !== "complete" || !record.session_id) return { status: "pending" };

  let sessionID = record.session_id;
  if (isSealed(sessionID)) {
    const key = await sessionKey(env);
    const opened = key ? await openSession(sessionID, key) : null;
    if (!opened) {
      // Key missing/rotated — the stored session is unrecoverable. Treat the
      // pairing as dead rather than handing out ciphertext.
      return { status: "missing" };
    }
    sessionID = opened;
  }

  const claimed: PairingRecord = {
    ...record,
    status: "claimed",
    session_id: undefined,
  };
  await env.PAIRING.put(pairingKey(code), JSON.stringify(claimed), {
    expirationTtl: MIN_TTL_SECONDS,
  });
  return { status: "complete", session_id: sessionID };
}

export function json(data: unknown, init: ResponseInit = {}): Response {
  const headers = new Headers(init.headers);
  headers.set("content-type", "application/json; charset=utf-8");
  headers.set("cache-control", "no-store");
  return new Response(JSON.stringify(data), { ...init, headers });
}

export const USER_AGENT =
  "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) PatreonTV/0.1";

export function parseSessionIDFromSetCookie(setCookie: string | null): string | null {
  if (!setCookie) return null;
  const match = setCookie.match(/(?:^|,|\s)session_id=([^;\s,]+)/i);
  return match?.[1] ?? null;
}

export function parseAllSessionIDs(headers: Headers): string | null {
  const getSetCookie = (headers as Headers & { getSetCookie?: () => string[] }).getSetCookie;
  if (typeof getSetCookie === "function") {
    for (const cookie of getSetCookie.call(headers)) {
      const session = parseSessionIDFromSetCookie(cookie);
      if (session) return session;
    }
  }
  return parseSessionIDFromSetCookie(headers.get("set-cookie"));
}

/** Thrown by exchangeOAuthCode with a URL-safe, non-leaking error code. */
export class OAuthExchangeError extends Error {
  readonly code: string;
  constructor(code: string) {
    super(code);
    this.code = code;
  }
}

export async function exchangeOAuthCode(
  env: PairingEnv,
  oauthCode: string,
  redirectUri: string,
): Promise<{ access_token: string; refresh_token?: string }> {
  if (!env.PATREON_CLIENT_ID || !env.PATREON_CLIENT_SECRET) {
    throw new OAuthExchangeError("oauth_not_configured");
  }

  const body = new URLSearchParams({
    code: oauthCode,
    grant_type: "authorization_code",
    client_id: env.PATREON_CLIENT_ID,
    client_secret: env.PATREON_CLIENT_SECRET,
    redirect_uri: redirectUri,
  });

  const resp = await fetch("https://www.patreon.com/api/oauth2/token", {
    method: "POST",
    headers: {
      "content-type": "application/x-www-form-urlencoded",
      "user-agent": USER_AGENT,
    },
    body,
  });
  if (!resp.ok) {
    // Upstream bodies must never end up in redirect URLs (they leak into
    // access logs and browser history) — map to a fixed code.
    throw new OAuthExchangeError("token_exchange_failed");
  }
  const tokens = (await resp.json()) as { access_token?: string; refresh_token?: string };
  if (!tokens.access_token) throw new OAuthExchangeError("token_exchange_failed");
  return { access_token: tokens.access_token, refresh_token: tokens.refresh_token };
}

/** Best-effort: some Patreon API responses include a session_id Set-Cookie. */
export async function bootstrapSessionFromAccessToken(accessToken: string): Promise<string | null> {
  const resp = await fetch(
    "https://www.patreon.com/api/current_user?fields[user]=full_name",
    {
      headers: {
        Authorization: `Bearer ${accessToken}`,
        Accept: "application/json",
        "User-Agent": USER_AGENT,
        Referer: "https://www.patreon.com/",
      },
      redirect: "manual",
    },
  );
  return parseAllSessionIDs(resp.headers);
}
