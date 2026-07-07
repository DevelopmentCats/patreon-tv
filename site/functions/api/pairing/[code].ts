import { claimPairingSession, formatCode, json, normalizeCode, type PairingEnv } from "../../_lib/pairing";

export const onRequestGet: PagesFunction<PairingEnv> = async ({ params, env }) => {
  const code = normalizeCode(String(params.code ?? ""));
  if (code.length !== 8) {
    return json({ error: "invalid_code" }, { status: 400 });
  }

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
