import {
  createPairing,
  formatCode,
  json,
  publicOrigin,
  type PairingEnv,
} from "../../_lib/pairing";
import { clientIP, rateLimit, rateLimited } from "../../_lib/rateLimit";

export const onRequestPost: PagesFunction<PairingEnv> = async ({ request, env }) => {
  // Unauthenticated KV-writing endpoint — throttle per IP.
  const limit = await rateLimit(env.PAIRING, "create", clientIP(request), 10, 60);
  if (!limit.allowed) return rateLimited();

  const record = await createPairing(env);
  const origin = publicOrigin(env, request);
  const linkURL = `${origin}/link/${formatCode(record.code)}`;

  return json({
    code: record.code,
    display_code: formatCode(record.code),
    link_url: linkURL,
    expires_at: record.expires_at,
    poll_url: `${origin}/api/pairing/${record.code}`,
  });
};
