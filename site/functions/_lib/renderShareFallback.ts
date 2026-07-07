// functions/_lib/renderShareFallback.ts
//
// Tiny HTML template shared by the share-fallback Pages Functions.
// Kept dependency-free so the Pages Function bundle stays small.

import { escapeHTML as escape } from "./html";

interface Params {
  kind: "post" | "creator";
  title: string;
  subtitle: string;
  primaryLabel: string;
  primaryHref: string;
  secondaryLabel: string;
  secondaryHref: string;
}

// Match the styles from src/layouts/Base.astro. Kept inline so the fallback
// pages don't ship a full Astro bundle for the sake of one page.
const STYLES = `
:root {
  --bg: #0a0a10;
  --surface: #14141b;
  --border: #24242e;
  --text: #ffffff;
  --text-muted: #a8a8b2;
  --text-dim: #6a6a75;
  --brand: #fa5040;
  --brand-hover: #ff6353;
  --radius: 12px;
  --max-width: 1080px;
}
* { box-sizing: border-box; }
html, body {
  margin: 0; padding: 0; background: var(--bg); color: var(--text);
  font-family: -apple-system, BlinkMacSystemFont, "SF Pro Text", "Segoe UI", Roboto, sans-serif;
  font-size: 17px; line-height: 1.55; -webkit-font-smoothing: antialiased;
}
body { min-height: 100vh; display: flex; flex-direction: column; }
main { flex: 1; width: 100%; max-width: var(--max-width); margin: 0 auto; padding: 40px 24px 80px; }
a { color: var(--brand); text-decoration: none; }
a:hover { color: var(--brand-hover); text-decoration: underline; }
h1 { font-size: clamp(2rem, 6vw, 3.75rem); font-weight: 700; margin: 0 0 24px; line-height: 1.2; }
p { margin: 0 0 16px; color: var(--text-muted); max-width: 65ch; }
.btn {
  display: inline-flex; align-items: center; gap: 8px;
  background: var(--brand); color: #fff; padding: 14px 28px;
  border-radius: 999px; font-weight: 600; text-decoration: none;
  transition: background 120ms ease;
}
.btn:hover { background: var(--brand-hover); text-decoration: none; }
.btn.secondary { background: transparent; color: var(--text); border: 1px solid var(--border); }
.btn.secondary:hover { background: var(--surface); }
header { max-width: var(--max-width); margin: 0 auto; padding: 24px; display: flex; align-items: center; justify-content: space-between; }
nav { display: flex; gap: 24px; font-size: 0.95rem; }
nav a { color: var(--text-muted); text-decoration: none; }
footer { border-top: 1px solid var(--border); padding: 32px 24px; text-align: center; color: var(--text-dim); font-size: 0.9rem; }
footer a { color: var(--text-muted); margin: 0 12px; }
`;

export function renderShareFallback(params: Params): string {
  const t = escape(params.title);
  return `<!doctype html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<meta name="color-scheme" content="dark">
<meta name="theme-color" content="#0a0a10">
<title>${t} — PatreonTV</title>
<meta name="description" content="${escape(params.subtitle)}">
<link rel="icon" href="/favicon.svg" type="image/svg+xml">
<style>${STYLES}</style>
</head>
<body>
<header>
  <a href="/" style="font-weight: 700; font-size: 1.15rem; color: var(--text); text-decoration: none;">
    Patreon<span style="color: var(--brand);">TV</span>
  </a>
  <nav>
    <a href="/support">Support</a>
    <a href="/privacy">Privacy</a>
    <a href="/terms">Terms</a>
  </nav>
</header>
<main>
  <div style="text-align: center; padding: 40px 0;">
    <h1>${t}</h1>
    <p style="max-width: 480px; margin: 0 auto 40px;">
      ${escape(params.subtitle)}
    </p>
    <div style="display: flex; gap: 12px; justify-content: center; flex-wrap: wrap;">
      <a class="btn" href="${escape(params.primaryHref)}">${escape(params.primaryLabel)}</a>
      <a class="btn secondary" href="${escape(params.secondaryHref)}" rel="noopener">
        ${escape(params.secondaryLabel)}
      </a>
    </div>
    <p style="margin-top: 60px; color: var(--text-dim); font-size: 0.9rem;">
      Don't have PatreonTV yet? <a href="/">Learn more</a>.
    </p>
  </div>
</main>
<footer>
  <p style="color: inherit; margin: 0 0 8px;">
    © 2026 PatreonTV. Not affiliated with, endorsed by, or sponsored by Patreon.
  </p>
  <p style="color: inherit; margin: 0;">
    <a href="/privacy">Privacy</a>
    <a href="/terms">Terms</a>
    <a href="/support">Support</a>
  </p>
</footer>
</body>
</html>`;
}
