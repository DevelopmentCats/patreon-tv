import {
  completePairing,
  formatCode,
  json,
  normalizeCode,
  type PairingEnv,
} from "../../_lib/pairing";
import { clientIP, rateLimit, rateLimited } from "../../_lib/rateLimit";

interface CompleteBody {
  code?: string;
  session_id?: string;
}

export const onRequestPost: PagesFunction<PairingEnv> = async ({ request, env }) => {
  // Accepts credential material against guessable codes — throttle hard.
  const limit = await rateLimit(env.PAIRING, "complete", clientIP(request), 10, 60);
  if (!limit.allowed) return rateLimited();

  let body: CompleteBody;
  try {
    body = (await request.json()) as CompleteBody;
  } catch {
    return json({ error: "invalid_json" }, { status: 400 });
  }

  const code = normalizeCode(String(body.code ?? ""));
  const sessionID = String(body.session_id ?? "").trim();
  if (code.length !== 8 || !sessionID) {
    return json({ error: "invalid_request" }, { status: 400 });
  }

  // completePairing rejects missing, expired, and already-claimed codes.
  const updated = await completePairing(env, code, sessionID);
  if (!updated) {
    return json({ error: "code_not_found", display_code: formatCode(code) }, { status: 404 });
  }

  return json({
    ok: true,
    display_code: formatCode(code),
    status: updated.status,
  });
};
