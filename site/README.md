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
| `/api/health` | JSON health endpoint for uptime monitoring |
| `/.well-known/apple-app-site-association` | Universal Links manifest (needs Team ID) |

## Local dev

```bash
cd site
npm install
npm run dev
```

Open http://localhost:4321.

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
