import { formatCode, normalizeCode, type PairingEnv } from "../_lib/pairing";
import { renderLinkPage } from "../_lib/renderLinkPage";

export const onRequestGet: PagesFunction<PairingEnv> = async ({ params, request, env }) => {
  const code = normalizeCode(String(params.code ?? ""));
  if (code.length !== 8) {
    return Response.redirect(new URL("/", request.url).toString(), 302);
  }

  const oauthEnabled = Boolean(env.PATREON_CLIENT_ID && env.PATREON_CLIENT_SECRET);

  const html = renderLinkPage({
    code,
    displayCode: formatCode(code),
    query: new URL(request.url).searchParams,
    oauthEnabled,
  });

  return new Response(html, {
    headers: {
      "content-type": "text/html; charset=utf-8",
      "cache-control": "no-store",
    },
  });
};
