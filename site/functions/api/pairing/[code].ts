import {
  claimPairingSession,
  formatCode,
  json,
  normalizeCode,
  pairingStatus,
  type PairingEnv,
} from "../../_lib/pairing";
import { clientIP, rateLimit, rateLimited } from "../../_lib/rateLimit";

/**
 * GET — non-consuming status check. Safe for prefetchers/scanners: it never
 * returns the session and never burns the pairing.
 */
export const onRequestGet: PagesFunction<PairingEnv> = async ({ params, request, env }) => {
  const code = normalizeCode(String(params.code ?? ""));
  if (code.length !== 8) {
    return json({ error: "invalid_code" }, { status: 400 });
  }

  const limit = await rateLimit(env.PAIRING, "status", clientIP(request), 90, 60);
  if (!limit.allowed) return rateLimited();

  const status = await pairingStatus(env, code);
  if (status === "missing") {
    return json({ status: "missing", display_code: formatCode(code) }, { status: 404 });
  }
  return json({ status, display_code: formatCode(code) });
};

/**
 * POST — claims the session (returned once, then the record is marked
 * claimed). The state change lives on POST so GETs stay side-effect free.
 */
export const onRequestPost: PagesFunction<PairingEnv> = async ({ params, request, env }) => {
  const code = normalizeCode(String(params.code ?? ""));
  if (code.length !== 8) {
    return json({ error: "invalid_code" }, { status: 400 });
  }

  // The TV polls every ~2s (≈30/min); 90/min leaves headroom without
  // enabling code spraying.
  const limit = await rateLimit(env.PAIRING, "claim", clientIP(request), 90, 60);
  if (!limit.allowed) return rateLimited();

  const result = await claimPairingSession(env, code);
  if (result.status === "missing") {
    return json({ status: "missing", display_code: formatCode(code) }, { status: 404 });
  }
  if (result.status === "pending") {
    return json({ status: "pending", display_code: formatCode(code) });
  }
  if (result.status === "claimed") {
    return json({ status: "claimed", display_code: formatCode(code) });
  }

  return json({
    status: "complete",
    display_code: formatCode(code),
    session_id: result.session_id,
  });
};
