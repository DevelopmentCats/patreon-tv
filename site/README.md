# PatreonTV — website

Marketing landing, privacy, terms, support, and deep-link fallback pages.
Built with [Astro](https://astro.build) and deploys to
[Cloudflare Pages](https://pages.cloudflare.com).

## What's on it

| Path | Purpose |
|---|---|
| `/` | Marketing landing page — "coming soon" hero + feature grid |
| `/privacy` | Privacy policy (required by Apple for App Store submission) |
| `/terms` | Terms of Service |
| `/support` | FAQ + contact — required for App Store listing (Support URL field) |
| `/post/:id` | Deep-link fallback for `patreontv://post/<id>` shares |
| `/creator/:id` | Deep-link fallback for `patreontv://creator/<id>` shares |
| `/link/:code` | Device-link sign-in portal (pair Apple TV with Patreon) |
| `/api/pairing/*` | Pairing API — create code, poll status, complete OAuth |
| `/.well-known/apple-app-site-association` | Universal Links manifest (needs Team ID) |

## Local dev

```bash
cd site
npm install
npm run dev
```

Open http://localhost:4321.

### Device-link sign-in (local dev — iPhone + Apple TV Simulator)

Run the pairing service on your **LAN IP** so your iPhone can scan the QR code.
The dev script auto-detects your Mac's IP and updates the tvOS DEBUG config.

```bash
cd site
npm install
npm run dev:pairing
```

This binds `0.0.0.0:8788` and sets `PAIRING_PUBLIC_ORIGIN` to e.g.
`http://192.168.1.148:8788`. Rebuild/run the tvOS app in Xcode (DEBUG).

On your iPhone (same Wi‑Fi): scan the QR on the TV, or open the link shown.
Use **Having trouble? Connect manually** to paste your `session_id` cookie.

Override the detected IP: `PAIRING_LAN_IP=10.0.0.5 npm run dev:pairing`

For fully automated OAuth, add to `site/.dev.vars` (see script output):

```
PATREON_CLIENT_ID=...
PATREON_CLIENT_SECRET=...
PATREON_REDIRECT_URI=http://<your-lan-ip>:8788/api/pairing/oauth/callback
```

| `/api/health` | JSON health endpoint for uptime monitoring |

## Deploy to Cloudflare Pages

### One-time setup (in Cloudflare dashboard)

1. Log in to [Cloudflare](https://dash.cloudflare.com).
2. **Workers & Pages** → **Create** → **Pages** → **Connect to Git** and
   point at this repo. Set:
   - Framework preset: **Astro**
   - Build command: `cd site && npm ci && npm run build`
   - Build output directory: `site/dist`
   - Root directory: `/` (repo root)
3. **Deploy**.
4. Once deployed, in the project's **Custom domains** tab, add
   `patreontv.app` (or whatever your production domain is). Cloudflare
   handles the TLS cert automatically.

### Command-line deploy (alternative)

If you'd rather deploy without the Git integration:

```bash
cd site
npm install
npm run deploy
```

This runs `astro build` then `wrangler pages deploy dist --project-name patreon-tv`.
You'll be prompted to log in on first use.

## Universal Links — before it works

The AASA file at `public/.well-known/apple-app-site-association`
currently has `TEAMID` as a placeholder. To enable Universal Links:

1. Look up your Apple Developer **Team ID** at
   <https://developer.apple.com/account>.
2. Replace `TEAMID` in `public/.well-known/apple-app-site-association`
   with the real value (looks like `A1B2C3D4E5`).
3. In Xcode, on the `PatreonTV` target → Signing & Capabilities → Add
   **Associated Domains** capability → add entry `applinks:patreontv.app`
   (matching your actual domain).
4. Ship the app. Universal Links start working after the app is
   installed and the AASA file is fetched by iOS/tvOS.

Until then, deep links via the `patreontv://` custom scheme still work
in-app (from Top Shelf, etc.); only the web fallback pages don't jump
automatically.
