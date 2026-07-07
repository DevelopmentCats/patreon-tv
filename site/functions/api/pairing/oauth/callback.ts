import {
  OAuthExchangeError,
  bootstrapSessionFromAccessToken,
  completePairing,
  exchangeOAuthCode,
  formatCode,
  publicOrigin,
  verifyOAuthNonce,
  type PairingEnv,
} from "../../../_lib/pairing";

/** Fixed error codes only — never raw upstream messages (they leak into
 *  access logs and browser history via the redirect URL). */
const KNOWN_ERRORS = new Set([
  "access_denied",
  "oauth_not_configured",
  "token_exchange_failed",
  "need_session",
  "expired",
  "invalid_state",
  "missing_code",
]);

export const onRequestGet: PagesFunction<PairingEnv> = async ({ request, env }) => {
  const url = new URL(request.url);
  const oauthError = url.searchParams.get("error");
  const state = url.searchParams.get("state") ?? "";
  const oauthCode = url.searchParams.get("code");

  // state = "<pairing-code>.<nonce>" (see oauth/start.ts)
  const [rawCode = "", nonce = ""] = state.split(".");
  const code = rawCode.replace(/[^A-Za-z0-9]/g, "").toUpperCase();

  if (!code || code.length !== 8) {
    return new Response("Invalid pairing state.", { status: 400 });
  }

  const linkPath = `/link/${formatCode(code)}`;
  const redirectWithError = (errorCode: string) => {
    const safe = KNOWN_ERRORS.has(errorCode) ? errorCode : "oauth_failed";
    return Response.redirect(new URL(`${linkPath}?error=${safe}`, request.url).toString(), 302);
  };

  if (oauthError) {
    return redirectWithError(oauthError === "access_denied" ? "access_denied" : "oauth_failed");
  }
  if (!oauthCode) {
    return redirectWithError("missing_code");
  }

  // The nonce binds this callback to the record created by oauth/start.ts.
  // A forged callback that only knows the (guessable) pairing code fails here.
  if (!(await verifyOAuthNonce(env, code, nonce))) {
    return redirectWithError("invalid_state");
  }

  try {
    const origin = publicOrigin(env, request);
    const redirectUri =
      env.PATREON_REDIRECT_URI ?? `${origin}/api/pairing/oauth/callback`;

    const tokens = await exchangeOAuthCode(env, oauthCode, redirectUri);
    const sessionID = await bootstrapSessionFromAccessToken(tokens.access_token);

    if (!sessionID) {
      // OAuth alone may not yield a web session cookie; fall back to manual on phone.
      return redirectWithError("need_session");
    }

    const updated = await completePairing(env, code, sessionID);
    if (!updated) {
      return redirectWithError("expired");
    }

    return Response.redirect(new URL(`${linkPath}?success=1`, request.url).toString(), 302);
  } catch (error) {
    return redirectWithError(error instanceof OAuthExchangeError ? error.code : "oauth_failed");
  }
};
