import { escapeHTML } from "./html";

interface LinkPageOptions {
  code: string;
  displayCode: string;
  query: URLSearchParams;
  /** Live KV status of the code, so dead codes don't render a working form. */
  codeStatus: "pending" | "complete" | "claimed" | "missing";
}

/** Human-readable messages for the fixed error codes surfaced via `?error=`. */
function errorMessage(error: string): string {
  switch (error) {
    case "expired":
      return "This pairing code expired. Start again from your Apple TV.";
    default:
      return "Something went wrong. Start again from your Apple TV to get a fresh code.";
  }
}

export function renderLinkPage({ code, displayCode, query, codeStatus }: LinkPageOptions): string {
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
  } else if (error) {
    statusHTML = `<div class="status error" role="status">${escapeHTML(errorMessage(error))}</div>`;
  }

  // The session_id cookie is HttpOnly, so it can't be read on a phone browser —
  // it only shows in a desktop browser's developer tools. The flow therefore
  // steers people to a computer.
  const flowHTML = codeDead || codeStatus === "claimed" || success
    ? ""
    : `<p class="lead">Connect this TV to your Patreon account in four steps. You'll need a <strong>computer</strong> — the sign-in cookie is hidden from phone browsers.</p>
        <div id="mobile-note" class="status warn" role="status" hidden>
          You're on a phone. Copying the cookie needs a desktop browser's developer tools — open <strong>patreontv.com/link/${escapeHTML(code)}</strong> on a computer, or type the code there.
        </div>
        <ol class="steps">
          <li><a href="https://www.patreon.com/login" target="_blank" rel="noopener">Sign in to patreon.com</a> in a desktop browser.</li>
          <li>Open developer tools (<kbd>⌥⌘I</kbd> on Mac, <kbd>F12</kbd> on Windows), then <strong>Application → Cookies → https://www.patreon.com</strong>.</li>
          <li>Copy the value of the <code>session_id</code> cookie.</li>
          <li>Paste it below and tap <strong>Connect TV</strong>.</li>
        </ol>
        <form id="manual-form">
          <label for="session_id">session_id</label>
          <input id="session_id" name="session_id" type="text" autocapitalize="off" autocorrect="off" autocomplete="off" spellcheck="false" placeholder="Paste cookie value" required />
          <button type="submit" class="button primary">Connect TV</button>
        </form>`;

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
    h1 { margin: 0 0 1.5rem; font-size: 1.75rem; }
    .code-label { margin: 0; opacity: 0.65; }
    .code {
      font-family: ui-monospace, SFMono-Regular, Menlo, monospace;
      font-size: 2rem;
      letter-spacing: 0.2em;
      margin: 0.25rem 0 0.5rem;
    }
    .code-note { margin: 0 0 1.5rem; font-size: 0.85rem; opacity: 0.6; }
    .lead { margin: 0 0 1.25rem; }
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
    .button.primary { background: #fa4f4d; color: white; margin-top: 1rem; }
    .status {
      margin: 0 0 1rem;
      padding: 0.85rem 1rem;
      border-radius: 12px;
      font-size: 0.95rem;
    }
    .status.ok { background: rgba(52,199,89,0.15); }
    .status.warn { background: rgba(255,204,0,0.15); }
    .status.error { background: rgba(255,69,58,0.15); }
    p { line-height: 1.5; opacity: 0.85; }
    ol.steps { opacity: 0.9; line-height: 1.7; padding-left: 1.25rem; margin: 0 0 0.5rem; }
    ol.steps li { margin-bottom: 0.35rem; }
    a { color: #fa7f7d; }
    code, kbd {
      font-family: ui-monospace, SFMono-Regular, Menlo, monospace;
      background: rgba(255,255,255,0.1);
      border-radius: 6px;
      padding: 0.1em 0.4em;
      font-size: 0.9em;
    }
    label { display: block; margin: 1.25rem 0 0.35rem; font-size: 0.85rem; opacity: 0.75; }
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
      <img src="/brand/wordmark.png" alt="PatreonTV" style="height: 28px; width: auto; margin-bottom: 1rem;" />
      <h1>Connect your Apple TV</h1>
      <p class="code-label">Pairing code</p>
      <p class="code">${escapeHTML(displayCode)}</p>
      <p class="code-note">Make sure this matches the code on your TV. Never connect a code someone sent you.</p>
      <div id="live-status" aria-live="polite">${statusHTML}</div>
      ${flowHTML}
    </div>
  </main>
  <script>
    const code = ${JSON.stringify(code)};
    const form = document.getElementById("manual-form");
    const liveStatus = document.getElementById("live-status");

    // The cookie is HttpOnly — unreadable on phones. Warn mobile visitors up front.
    if (/Mobi|Android|iPhone|iPad|iPod/i.test(navigator.userAgent)) {
      document.getElementById("mobile-note")?.removeAttribute("hidden");
    }

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
      form.setAttribute("hidden", "hidden");
    });
  </script>
</body>
</html>`;
}
