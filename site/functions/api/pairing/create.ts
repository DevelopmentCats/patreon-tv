import {
  createPairing,
  formatCode,
  json,
  publicOrigin,
  type PairingEnv,
} from "../../_lib/pairing";

export const onRequestPost: PagesFunction<PairingEnv> = async ({ request, env }) => {
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
