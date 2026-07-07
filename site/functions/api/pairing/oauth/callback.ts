import {
  bootstrapSessionFromAccessToken,
  completePairing,
  exchangeOAuthCode,
  formatCode,
  publicOrigin,
  type PairingEnv,
} from "../../../_lib/pairing";

export const onRequestGet: PagesFunction<PairingEnv> = async ({ request, env }) => {
  const url = new URL(request.url);
  const oauthError = url.searchParams.get("error");
  const code = (url.searchParams.get("state") ?? "").replace(/[^A-Za-z0-9]/g, "").toUpperCase();
  const oauthCode = url.searchParams.get("code");

  if (!code || code.length !== 8) {
    return new Response("Invalid pairing state.", { status: 400 });
  }

  const linkPath = `/link/${formatCode(code)}`;

  if (oauthError) {
    return Response.redirect(
      new URL(`${linkPath}?error=${encodeURIComponent(oauthError)}`, request.url),
      302,
    );
  }
  if (!oauthCode) {
    return Response.redirect(new URL(`${linkPath}?error=missing_code`, request.url), 302);
  }

  try {
    const origin = publicOrigin(env, request);
    const redirectUri =
      env.PATREON_REDIRECT_URI ?? `${origin}/api/pairing/oauth/callback`;

    const tokens = await exchangeOAuthCode(env, oauthCode, redirectUri);
    let sessionID = await bootstrapSessionFromAccessToken(tokens.access_token);

    if (!sessionID) {
      // OAuth alone may not yield a web session cookie; fall back to manual on phone.
      return Response.redirect(new URL(`${linkPath}?error=need_session`, request.url), 302);
    }

    const updated = await completePairing(env, code, sessionID);
    if (!updated) {
      return Response.redirect(new URL(`${linkPath}?error=expired`, request.url), 302);
    }

    return Response.redirect(new URL(`${linkPath}?success=1`, request.url), 302);
  } catch (error) {
    const message = error instanceof Error ? error.message : "oauth_failed";
    return Response.redirect(
      new URL(`${linkPath}?error=${encodeURIComponent(message)}`, request.url),
      302,
    );
  }
};
