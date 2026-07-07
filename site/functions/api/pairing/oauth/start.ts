import {
  formatCode,
  issueOAuthNonce,
  normalizeCode,
  publicOrigin,
  type PairingEnv,
} from "../../../_lib/pairing";
import { escapeHTML } from "../../../_lib/html";

/**
 * Starts the Patreon OAuth round-trip for a pairing code.
 *
 * Device-flow phishing defense: an attacker who creates a code on THEIR TV
 * could send a victim this URL and harvest the victim's session. Two
 * mitigations:
 *  1. An interstitial confirmation page shows the code and asks the user to
 *     verify it matches the code on their own TV before continuing.
 *  2. The OAuth `state` carries a random per-record nonce (not just the
 *     attacker-knowable code), so forged callbacks can't complete a pairing.
 */
export const onRequestGet: PagesFunction<PairingEnv> = async ({ request, env }) => {
  const url = new URL(request.url);
  const code = normalizeCode(url.searchParams.get("code") ?? "");
  if (code.length !== 8) {
    return new Response("Missing or invalid pairing code.", { status: 400 });
  }
  if (!env.PATREON_CLIENT_ID || !env.PATREON_CLIENT_SECRET) {
    return Response.redirect(new URL(`/link/${code}?error=oauth_not_configured`, request.url).toString(), 302);
  }

  // First visit: show the confirm interstitial instead of bouncing straight
  // to Patreon.
  if (url.searchParams.get("confirm") !== "1") {
    return new Response(renderConfirmPage(code), {
      headers: {
        "content-type": "text/html; charset=utf-8",
        "cache-control": "no-store",
      },
    });
  }

  const nonce = await issueOAuthNonce(env, code);
  if (!nonce) {
    // Missing, expired, or already completed — send them back to the link page.
    return Response.redirect(new URL(`/link/${code}?error=expired`, request.url).toString(), 302);
  }

  const origin = publicOrigin(env, request);
  const redirectUri =
    env.PATREON_REDIRECT_URI ?? `${origin}/api/pairing/oauth/callback`;

  const authorize = new URL("https://www.patreon.com/oauth2/authorize");
  authorize.searchParams.set("response_type", "code");
  authorize.searchParams.set("client_id", env.PATREON_CLIENT_ID);
  authorize.searchParams.set("redirect_uri", redirectUri);
  // Minimal scope: the callback only probes /current_user for a session
  // cookie. The wider campaign/post scopes were never used.
  authorize.searchParams.set("scope", "identity");
  authorize.searchParams.set("state", `${code}.${nonce}`);

  return Response.redirect(authorize.toString(), 302);
};

function renderConfirmPage(code: string): string {
  const display = escapeHTML(formatCode(code));
  const continueHref = `/api/pairing/oauth/start?code=${escapeHTML(code)}&confirm=1`;
  return `<!doctype html>
<html lang="en">
<head>
  <meta charset="utf-8" />
  <meta name="viewport" content="width=device-width, initial-scale=1" />
  <meta name="color-scheme" content="dark" />
  <title>Confirm pairing code — PatreonTV</title>
  <style>
    :root { color-scheme: dark; }
    body { margin: 0; font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", sans-serif; background: #0a0a10; color: #fff; }
    main { min-height: 100vh; display: grid; place-items: center; padding: 2rem 1rem; }
    .card { width: min(560px, 100%); background: rgba(255,255,255,0.04); border: 1px solid rgba(255,255,255,0.08); border-radius: 20px; padding: 2rem; }
    h1 { margin: 0 0 1rem; font-size: 1.5rem; }
    .code { font-family: ui-monospace, SFMono-Regular, Menlo, monospace; font-size: 2rem; letter-spacing: 0.2em; margin: 0.5rem 0 1.5rem; }
    p { line-height: 1.5; opacity: 0.85; }
    .warn { background: rgba(255,204,0,0.12); border-radius: 12px; padding: 0.85rem 1rem; font-size: 0.95rem; }
    .button { display: block; text-decoration: none; border-radius: 999px; padding: 0.85rem 1.25rem; font-weight: 600; text-align: center; margin-top: 1.25rem; }
    .button.primary { background: #fa4f4d; color: #fff; }
    .button.secondary { background: rgba(255,255,255,0.12); color: #fff; margin-top: 0.75rem; }
  </style>
</head>
<body>
  <main>
    <div class="card">
      <h1>Does this code match your Apple TV?</h1>
      <p class="code">${display}</p>
      <p class="warn">Only continue if this exact code is showing on <strong>your own</strong> Apple TV right now. If someone sent you this link, stop — signing in would connect <em>your</em> Patreon account to <em>their</em> TV.</p>
      <a class="button primary" href="${continueHref}">Yes, that's my TV — sign in with Patreon</a>
      <a class="button secondary" href="/">Cancel</a>
    </div>
  </main>
</body>
</html>`;
}
