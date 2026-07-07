export interface PairingEnv {
  PAIRING: KVNamespace;
  PATREON_CLIENT_ID?: string;
  PATREON_CLIENT_SECRET?: string;
  /** OAuth redirect, e.g. https://patreontv.app/api/pairing/oauth/callback */
  PATREON_REDIRECT_URI?: string;
  /** Public site origin for link URLs, e.g. https://patreontv.app */
  PAIRING_PUBLIC_ORIGIN?: string;
}

export interface PairingRecord {
  code: string;
  status: "pending" | "complete" | "claimed";
  created_at: string;
  expires_at: string;
  session_id?: string;
}

const CODE_ALPHABET = "ABCDEFGHJKLMNPQRSTUVWXYZ23456789";
const TTL_SECONDS = 10 * 60;

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
  const bytes = crypto.getRandomValues(new Uint8Array(8));
  let code = "";
  for (const byte of bytes) {
    code += CODE_ALPHABET[byte % CODE_ALPHABET.length];
  }
  return code.slice(0, 8);
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

export async function readPairing(env: PairingEnv, code: string): Promise<PairingRecord | null> {
  const raw = await env.PAIRING.get(pairingKey(code));
  if (!raw) return null;
  const record = JSON.parse(raw) as PairingRecord;
  if (Date.now() > Date.parse(record.expires_at)) {
    return { ...record, status: "pending", session_id: undefined };
  }
  return record;
}

export async function completePairing(
  env: PairingEnv,
  code: string,
  sessionID: string,
): Promise<PairingRecord | null> {
  const record = await readPairing(env, code);
  if (!record || record.status === "claimed") return null;
  const updated: PairingRecord = {
    ...record,
    status: "complete",
    session_id: sessionID.trim(),
  };
  await env.PAIRING.put(pairingKey(code), JSON.stringify(updated), {
    expirationTtl: TTL_SECONDS,
  });
  return updated;
}

/** TV polls until complete; returns session once then marks claimed. */
export async function claimPairingSession(
  env: PairingEnv,
  code: string,
): Promise<{ status: "pending" | "complete" | "claimed" | "missing"; session_id?: string }> {
  const record = await readPairing(env, code);
  if (!record) return { status: "missing" };
  if (Date.now() > Date.parse(record.expires_at)) return { status: "missing" };
  if (record.status === "claimed") return { status: "claimed" };
  if (record.status !== "complete" || !record.session_id) return { status: "pending" };

  const claimed: PairingRecord = {
    ...record,
    status: "claimed",
    session_id: undefined,
  };
  await env.PAIRING.put(pairingKey(code), JSON.stringify(claimed), {
    expirationTtl: 60,
  });
  return { status: "complete", session_id: record.session_id };
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

export async function exchangeOAuthCode(
  env: PairingEnv,
  oauthCode: string,
  redirectUri: string,
): Promise<{ access_token: string; refresh_token?: string }> {
  if (!env.PATREON_CLIENT_ID || !env.PATREON_CLIENT_SECRET) {
    throw new Error("Patreon OAuth is not configured on this deployment.");
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
  const text = await resp.text();
  if (!resp.ok) {
    throw new Error(`Token exchange failed (${resp.status}): ${text.slice(0, 300)}`);
  }
  const tokens = JSON.parse(text) as { access_token?: string; refresh_token?: string };
  if (!tokens.access_token) throw new Error("Token response missing access_token.");
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
