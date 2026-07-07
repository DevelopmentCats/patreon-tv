// functions/_lib/rateLimit.ts
//
// Best-effort, fixed-window rate limiter backed by the PAIRING KV namespace.
//
// KV is eventually consistent, so this is NOT an exact limiter — concurrent
// requests racing the counter can slip through. It exists to blunt casual
// abuse (unauthenticated KV writes on /create, code guessing on /complete).
// For hard guarantees put a Cloudflare WAF rate-limiting rule or Turnstile in
// front of these endpoints; this is defense-in-depth, not the only layer.

export interface RateLimitResult {
  allowed: boolean;
  remaining: number;
}

interface WindowRecord {
  count: number;
  windowStart: number;
}

export function clientIP(request: Request): string {
  return request.headers.get("cf-connecting-ip") ?? "unknown";
}

/**
 * @param scope   logical bucket, e.g. "create" | "complete" | "claim"
 * @param limit   max requests per window
 * @param windowSeconds  fixed window length
 */
export async function rateLimit(
  kv: KVNamespace,
  scope: string,
  identifier: string,
  limit: number,
  windowSeconds: number,
): Promise<RateLimitResult> {
  const key = `rl:${scope}:${identifier}`;
  const now = Date.now();

  let record: WindowRecord = { count: 0, windowStart: now };
  const raw = await kv.get(key);
  if (raw) {
    try {
      const parsed = JSON.parse(raw) as WindowRecord;
      if (now - parsed.windowStart < windowSeconds * 1000) {
        record = parsed;
      }
    } catch {
      // corrupted counter — start a fresh window
    }
  }

  if (record.count >= limit) {
    return { allowed: false, remaining: 0 };
  }

  record.count += 1;
  await kv.put(key, JSON.stringify(record), {
    // KV requires a minimum TTL of 60 seconds.
    expirationTtl: Math.max(windowSeconds, 60),
  });

  return { allowed: true, remaining: limit - record.count };
}

export function rateLimited(): Response {
  return new Response(JSON.stringify({ error: "rate_limited" }), {
    status: 429,
    headers: {
      "content-type": "application/json; charset=utf-8",
      "retry-after": "60",
      "cache-control": "no-store",
    },
  });
}
