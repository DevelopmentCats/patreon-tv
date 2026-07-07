import { normalizeCode, publicOrigin, type PairingEnv } from "../../../_lib/pairing";

export const onRequestGet: PagesFunction<PairingEnv> = async ({ request, env }) => {
  const url = new URL(request.url);
  const code = normalizeCode(url.searchParams.get("code") ?? "");
  if (code.length !== 8) {
    return new Response("Missing or invalid pairing code.", { status: 400 });
  }
  if (!env.PATREON_CLIENT_ID || !env.PATREON_CLIENT_SECRET) {
    return Response.redirect(new URL(`/link/${code}?error=oauth_not_configured`, request.url), 302);
  }

  const origin = publicOrigin(env, request);
  const redirectUri =
    env.PATREON_REDIRECT_URI ?? `${origin}/api/pairing/oauth/callback`;

  const authorize = new URL("https://www.patreon.com/oauth2/authorize");
  authorize.searchParams.set("response_type", "code");
  authorize.searchParams.set("client_id", env.PATREON_CLIENT_ID);
  authorize.searchParams.set("redirect_uri", redirectUri);
  authorize.searchParams.set(
    "scope",
    "identity identity[email] identity.memberships campaigns campaigns.posts",
  );
  authorize.searchParams.set("state", code);

  return Response.redirect(authorize.toString(), 302);
};
