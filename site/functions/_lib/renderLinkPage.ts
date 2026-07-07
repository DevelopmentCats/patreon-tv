import { escapeHTML } from "./html";

interface LinkPageOptions {
  code: string;
  displayCode: string;
  query: URLSearchParams;
  oauthEnabled: boolean;
  /** Live KV status of the code, so dead codes don't render a working form. */
  codeStatus: "pending" | "complete" | "claimed" | "missing";
}

/** Human-readable messages for the fixed error codes the OAuth callback emits. */
function errorMessage(error: string): string {
  switch (error) {
    case "need_session":
      return "Signed in with Patreon, but we still need your session cookie — paste it below.";
    case "expired":
      return "This pairing code expired. Start again from your Apple TV.";
    case "access_denied":
      return "Patreon sign-in was cancelled. You can try again or connect manually below.";
    case "invalid_state":
      return "This sign-in link is stale or invalid. Go back to your Apple TV and start again.";
    case "token_exchange_failed":
      return "Patreon sign-in failed. Try again in a moment, or connect manually below.";
    default:
      return "Sign-in failed. Try again, or connect manually below.";
  }
}

export function renderLinkPage({ code, displayCode, query, oauthEnabled, codeStatus }: LinkPageOptions): string {
  const success = query.get("success") === "1" || codeStatus === "claimed";
  const error = query.get("error");
  // A missing code is expired or was never issued: render a clear dead-end
  // instead of a form whose submission can never succeed.
  const codeDead = codeStatus === "missing";

  let statusHTML = "";

  if (codeDead) {
    statusHTML = `<div class="status error" role="status">This pairing code isn't active — it may have expired. Start again from your Apple TV to get a fresh code.</div>`;
  } else if (codeStatus === "claimed") {
    statusHTML = `<div class="status ok" role="status">This code was already used — your Apple TV should be signed in. If it isn't, start again from the TV.</div>`;
  } else if (success) {
    statusHTML = `<div class="status ok" role="status">You're connected. Return to your Apple TV — it should sign in automatically.</div>`;
  } else if (error && error !== "oauth_not_configured") {
    const kind = error === "need_session" ? "warn" : "error";
    statusHTML = `<div class="status ${kind}" role="status">${escapeHTML(errorMessage(error))}</div>`;
  }

  const oauthBlock = oauthEnabled && !success && !codeDead
    ? `<a class="button primary" id="oauth-btn" href="/api/pairing/oauth/start?code=${escapeHTML(code)}">Sign in with Patreon</a>`
    : "";

  const manualIntro = oauthEnabled
    ? `<details class="manual"${error === "need_session" ? " open" : ""}>
        <summary>Having trouble? Connect manually</summary>
        <p>After signing in at patreon.com, paste your <code>session_id</code> cookie below.</p>`
    : `<div class="manual manual-primary">
        <p><strong>Local dev:</strong> sign in at patreon.com on this device, then paste your <code>session_id</code> cookie below. (OAuth is not configured — that's normal for local testing.)</p>
        <ol class="steps">
          <li>Open <a href="https://www.patreon.com/login" target="_blank" rel="noopener">patreon.com/login</a> and sign in.</li>
          <li>Copy the <code>session_id</code> cookie from your browser (DevTools → Application → Cookies).</li>
          <li>Paste it here and tap Connect TV.</li>
        </ol>`;

  const manualClose = oauthEnabled ? `</details>` : `</div>`;

  const manualHTML = codeDead || codeStatus === "claimed"
    ? ""
    : `${manualIntro}
        <form id="manual-form">
          <label for="session_id">session_id</label>
          <input id="session_id" name="session_id" type="text" autocapitalize="off" autocorrect="off" autocomplete="off" placeholder="Paste cookie value" required />
          <button type="submit" class="button secondary">Connect TV</button>
        </form>
      ${manualClose}`;

  return `<!doctype html>
<html lang="en">
<head>
  <meta charset="utf-8" />
  <meta name="viewport" content="width=device-width, initial-scale=1" />
  <meta name="color-scheme" content="dark" />
  <title>Link Apple TV — PatreonTV</title>
  <style>
    :root { color-scheme: dark; }
    body {
      margin: 0;
      font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", sans-serif;
      background: #0a0a10;
      color: #fff;
    }
    main {
      min-height: 100vh;
      display: grid;
      place-items: center;
      padding: 2rem 1rem 4rem;
    }
    .card {
      width: min(560px, 100%);
      background: rgba(255,255,255,0.04);
      border: 1px solid rgba(255,255,255,0.08);
      border-radius: 20px;
      padding: 2rem;
    }
    .eyebrow {
      text-transform: uppercase;
      letter-spacing: 0.12em;
      font-size: 0.75rem;
      opacity: 0.6;
      margin: 0 0 0.5rem;
    }
    h1 { margin: 0 0 1.5rem; font-size: 1.75rem; }
    .code-label { margin: 0; opacity: 0.65; }
    .code {
      font-family: ui-monospace, SFMono-Regular, Menlo, monospace;
      font-size: 2rem;
      letter-spacing: 0.2em;
      margin: 0.25rem 0 0.5rem;
    }
    .code-note { margin: 0 0 1.5rem; font-size: 0.85rem; opacity: 0.6; }
    .button {
      display: block;
      text-decoration: none;
      border: none;
      border-radius: 999px;
      padding: 0.85rem 1.25rem;
      font-weight: 600;
      cursor: pointer;
      text-align: center;
      width: 100%;
      box-sizing: border-box;
      font-size: 1rem;
    }
    .button.primary { background: #fa4f4d; color: white; margin-bottom: 1rem; }
    .button.secondary {
      background: rgba(255,255,255,0.12);
      color: white;
      margin-top: 0.75rem;
    }
    .status {
      margin: 0 0 1rem;
      padding: 0.85rem 1rem;
      border-radius: 12px;
      font-size: 0.95rem;
    }
    .status.ok { background: rgba(52,199,89,0.15); }
    .status.warn { background: rgba(255,204,0,0.15); }
    .status.error { background: rgba(255,69,58,0.15); }
    .manual { margin-top: 1.5rem; font-size: 0.95rem; }
    .manual-primary { margin-top: 0.5rem; }
    summary { cursor: pointer; color: #fa4f4d; }
    p { line-height: 1.5; opacity: 0.85; }
    ol.steps { opacity: 0.85; line-height: 1.6; padding-left: 1.25rem; }
    a { color: #fa7f7d; }
    label { display: block; margin-bottom: 0.35rem; font-size: 0.85rem; opacity: 0.75; }
    input[type="text"] {
      width: 100%;
      box-sizing: border-box;
      border-radius: 10px;
      border: 1px solid rgba(255,255,255,0.15);
      background: rgba(0,0,0,0.25);
      color: white;
      padding: 0.75rem 0.85rem;
      font-family: ui-monospace, SFMono-Regular, Menlo, monospace;
      font-size: 16px;
    }
    [hidden] { display: none !important; }
  </style>
</head>
<body>
  <main>
    <div class="card">
      <p class="eyebrow">PatreonTV</p>
      <h1>Connect your Apple TV</h1>
      <p class="code-label">Pairing code</p>
      <p class="code">${escapeHTML(displayCode)}</p>
      <p class="code-note">Make sure this matches the code on your TV. Never sign in for a code someone sent you.</p>
      <div id="live-status" aria-live="polite">${statusHTML}</div>
      ${oauthBlock}
      ${manualHTML}
    </div>
  </main>
  <script>
    const code = ${JSON.stringify(code)};
    const form = document.getElementById("manual-form");
    const liveStatus = document.getElementById("live-status");
    function setStatus(kind, text) {
      let status = liveStatus.querySelector(".status");
      if (!status) {
        status = document.createElement("div");
        status.setAttribute("role", "status");
        liveStatus.appendChild(status);
      }
      status.className = "status " + kind;
      status.textContent = text;
    }
    form?.addEventListener("submit", async (event) => {
      event.preventDefault();
      const sessionId = document.getElementById("session_id").value.trim();
      if (!sessionId) return;
      const resp = await fetch("/api/pairing/complete", {
        method: "POST",
        headers: { "content-type": "application/json" },
        body: JSON.stringify({ code, session_id: sessionId }),
      });
      if (!resp.ok) {
        setStatus("error", "Could not connect. Check the code on your TV and try again.");
        return;
      }
      setStatus("ok", "Connected. Your Apple TV should sign in within a few seconds.");
      // Don't leave the session cookie sitting on-screen after success.
      document.getElementById("session_id").value = "";
      form.closest(".manual")?.setAttribute("hidden", "hidden");
      form.setAttribute("hidden", "hidden");
      document.getElementById("oauth-btn")?.setAttribute("hidden", "hidden");
    });
  </script>
</body>
</html>`;
}
