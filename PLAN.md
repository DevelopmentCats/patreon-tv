# Patreon on Apple TV — Consolidated Research & Decision Doc

Written 2026-07-06 after live doc fetching, forum research, GitHub prior-art
review, and library evaluation. Full evidence in:

- `docs/patreon-api-docs.md` — extracted Patreon official API docs (source of truth)
- `docs/patreon-research.md` — 1,185-line evidence-based research report (forum quotes, ToS, App Store precedent, community reverse-engineering)
- `docs/library-research.md` — 552-line library evaluation (tvOS + backend)
- `docs/patreon-internal-api-openapi.yaml` — 1,179-line reverse-engineered OpenAPI spec of Patreon's *internal* web API (community-maintained, actively updated)
- `PatreonTV/` — cloned open-source reference tvOS app (`kochj23/PatreonTV` v3.0.0, MIT, 2026-05, ~5,300 LOC, zero external deps)

## 1. The core reality (this changes everything)

Every prior plan assumed we could build the app on Patreon's **public OAuth API**. That assumption was wrong, and I need to correct it clearly.

### 1.1 The public API cannot build the app you want

Directly quoted from Patreon staff (`docs/patreon-research.md`):

> "There is no public api to list available posts / feed for patrons. Official android and iOS clients use internal apis which should not be used by 3rd parties — the endpoints may change and requests could get blocked by Patreon security rules."
> — Patreon staff @noertap, developer forum, 2025-12-15

> "The embed_url returns the link attached to a post, if the post was a 'link' post type. **Media / images attached to the post is not available via the api.**"
> — Patreon staff @noertap, 2026-06-19

> "Some work on the api is being mulled, however implementing PKCE is not among the potential changes at this moment."
> — @codebard, 2022-02-07

Consequences for a fan-facing consumer app:

1. **No fan feed endpoint.** Public API has no "posts from creators I support."
2. **No playable media URLs.** Post v2 exposes `embed_url` (for `link` post type only, per staff quote) and no `media` relationship. Post content is opaque to the API.
3. **No native app OAuth.** No PKCE, no device-authorization grant, no custom-URL-scheme redirect. `client_secret` must live on a server.
4. **API is in maintenance mode.** Patreon's own docs: "Our team is focused on developing our core product at this time. Endpoints will continue to function as normal." No new consumer capabilities planned.

The "participating creators program" pattern I proposed earlier (creators authorize our app one by one, we read their posts with their tokens) has a further problem I underweighted: **even a creator-authorized token gives us `campaigns.posts`, but the post objects still lack playable media relationships.** So we could list post titles and text, but not play videos, even with 100% creator opt-in.

### 1.2 The only path that actually plays video

The one working open-source Apple TV Patreon client (`kochj23/PatreonTV`, verified, cloned into this workspace) does not use the public API at all. It:

1. Runs a **macOS companion app** ("Relay") on the user's local network.
2. Opens a `WKWebView` in the Relay, loads `patreon.com/login`, and lets the user log in normally.
3. Extracts the `session_id` cookie from the WebView.
4. Uses that cookie to authenticate calls to Patreon's **internal web API** (`https://www.patreon.com/api/...`, e.g. `/api/stream`, `/api/posts/{id}`, `/api/current_user/memberships`, `/api/campaigns/{id}/posts`).
5. For Patreon-hosted video/audio: proxies the CDN URL through the Relay with the session cookie attached.
6. For YouTube/Vimeo embeds: runs `yt-dlp` as a subprocess to extract a direct HLS/MP4 URL, 302-redirects the Apple TV to it.
7. Apple TV never talks to Patreon; only to the Relay on the LAN.

This is architecturally clever and works, but it means:
- The user needs a Mac running 24/7 for the app to function
- The internal API is undocumented and can break/get blocked at any time
- The community-maintained OpenAPI spec of the internal API is the closest thing to documentation (`docs/patreon-internal-api-openapi.yaml`, 1,179 lines, updated 2026-06)

Post types confirmed from that spec: `post`, `podcast`, `text_only`, `image_file`, `link`, `video_embed`, `video_external_file`, `audio_embed`, `audio_file`, `poll`, `livestream_youtube`, `livestream_crowdcast`.

### 1.3 The regulatory picture

- **Patreon ToS v2 (2026-05-27):** grants fans "a non-exclusive, non-transferable, non-sublicensable, revocable, limited license to access and view [creator] creations for your own private, personal, non-promotional, non-commercial use." A viewer app for a fan's own paid content likely fits; redistribution or public display does not.
- **Patreon's forbidden-use clause:** reproducing / preparing derivative works of Patreon's own IP (including the API) is prohibited "unless we give you permission in writing." Using the internal API is squarely in this gray zone.
- **Apple's App Store, October 2024:** Apple compelled Patreon onto IAP for new memberships. Any third-party consumer client that even *looks* like it lets you subscribe outside IAP will face rejection. The reader-app exemption ("view content you already paid for elsewhere") may apply but is not guaranteed — Apple review is subjective.

## 2. The three viable product shapes

Given the above, there are exactly three product shapes that could realistically ship. Pick one before writing Swift.

### Shape A — Personal LAN app (the reference-app pattern)

- User runs a Mac companion (or a small self-hosted service on a Raspberry Pi / Synology / their own always-on Mac) that logs in as them via WebView and holds the session cookie.
- Apple TV client talks to the companion, never to Patreon.
- Distribution: sideload / TestFlight / **not App Store**. Or App Store as "requires companion Mac app" — probably rejectable under 4.2 (Minimum Functionality) if the tvOS app can't work without another purchase, but sideload/TestFlight is fine.
- Risks: Patreon can block the internal API at any time. Cloudflare occasionally 403s legitimate traffic; community workarounds exist (`curl-cffi` browser TLS fingerprinting) but they add fragility.
- Precedent: `kochj23/PatreonTV` (proven, actively maintained), `miniBill/secretdemoclub` (OpenAPI spec + working code), `shizukusoft/PatronArchiver` (allegedly App Store shipped — I could not independently verify this; App Store URL 404s to unauthenticated `curl`).

### Shape B — Cloud service that pairs with Patreon on user's behalf

- We run a backend service. User signs into Patreon via a browser popup on their phone, we extract the session cookie server-side, we hold and rotate it.
- Apple TV talks to our backend, which talks to Patreon internal API on user's behalf.
- Distribution: App Store possible but risky — Apple would review the auth flow closely.
- Risks: **All of Shape A's risks, plus you now hold thousands of users' Patreon session cookies.** That is a security posture I would not want. If Patreon rotates their internal API, thousands of users break simultaneously.
- I would not recommend this.

### Shape C — Official-only, degraded functionality

- Only use the documented public API. Register a creator-onboarded OAuth client.
- Show only creators who explicitly authorize our app (as we discussed).
- **Do not attempt to play video** — because the public API doesn't expose playable URLs. Show titles, text content, images, and a "watch on patreon.com" deep link.
- This is a **catalog / notification / text-reader** app for Patreon, not a "sit on the couch and watch" app.
- Distribution: App Store, likely no issues.
- Risks: minimal API-side, but the product is not what you asked for. This isn't a Netflix-style app; it's a Patreon RSS reader with prettier UI.

## 3. My recommendation

**Ship Shape A.** Here's why:

1. It's the only shape where the app *actually works* for the "watch Patreon on my TV" use case. Everything else is a compromise the user will feel every day.
2. There's proven prior art we can build on (`PatreonTV`, MIT-licensed — we can fork it or use it as a reference implementation).
3. The LAN-only architecture keeps user credentials off our servers and dramatically reduces our attack surface / operational burden.
4. It's honest with the user: "This app requires a Mac (or small home server) that stays on your network to work. It uses your Patreon login. It's not affiliated with Patreon."
5. TestFlight distribution is fine for a personal-use, one-Mac-per-household app. If you later want it in the App Store, we can explore the reader-app exemption carefully, but sideload is a totally legitimate distribution channel for a niche pro app.

**Alternative if App Store distribution is non-negotiable:** ship Shape C (public API, text/images only, no video) and be honest about what it is — "your Patreon inbox on your TV." This is a real product with real users but it isn't the couch-video app.

**Do not ship Shape B.** Holding user session cookies in a cloud service is a bad idea.

## 4. Assuming Shape A: the actual technical plan

### 4.1 Architecture (adapted from the reference app but improved)

```
Apple TV (tvOS 17+)
├── SwiftUI UI (Home, Creator, Post detail, Player)
├── AVPlayerViewController for video (native, HDR, PiP, AirPlay, HLS/MP4/FairPlay)
├── Nuke for image cache (shelves render 60fps)
├── Keychain-stored session token from Companion
├── Bonjour discovery of Companion on LAN
└── HTTP client to Companion for API + media proxy

Companion (macOS 14+, later: also Linux/Docker for headless home servers)
├── HTTP server on :8080 with Bonjour advertisement
├── WKWebView (macOS) or web-view alternative (Linux) for Patreon login
├── Session cookie extraction & rotation
├── Patreon internal API client (calls /api/stream, /api/posts, etc.)
├── Media proxy with Range/seek support
├── yt-dlp subprocess for YouTube/Vimeo embeds
├── URL cache (5-min TTL)
└── Dashboard UI (streams, stats, session status)
```

Departures from the reference app I'd make:

- **Ship a Linux/Docker companion in addition to Mac.** Many users have home servers (Synology, unRAID, Proxmox, Raspberry Pi). Mac-only is a big friction point. Login can happen once via any browser on any device, cookies land in the server via a paired shortcode. This is more work but a much better product.
- **Better error handling for Cloudflare 403s.** The reference app doesn't handle this. Add TLS fingerprint spoofing via a `curl-cffi`-equivalent-in-Swift path or (if we go Linux companion) use `curl-cffi` on the server side.
- **Design system that actually feels like Netflix.** The reference app has a "glassmorphic" style; we'd do something more like TV+/Netflix: hero art, coordinated shelves, focus-driven crossfades, autoplay-on-dwell previews.
- **Multiple user profiles on one companion.** The reference is single-user. If your household has two Patreon accounts, you should be able to switch on the TV.

### 4.2 tvOS stack (from `docs/library-research.md`, HIGH confidence)

| Layer | Choice | Rationale |
|---|---|---|
| Language | Swift 5.9+ / tvOS 17+ | SwiftUI focus APIs are meaningfully better on 17 |
| UI | SwiftUI primary, UIKit escape hatch | Standard for new tvOS in 2025 |
| Focus / shelves | Native (`focusable`, `focusEffect`, `focusSection`) + `LazyHStack`; UIKit `UICollectionViewCompositionalLayout` for anything complex | No Netflix-shelves-in-a-box library exists |
| Image cache | Nuke + NukeUI | Best request coalescing, tvOS declared in `Package.swift`, actively released |
| Video | `AVPlayerViewController` | Free HDR, PiP, AirPlay, HLS, FairPlay, native tvOS UI. Skip Bitmovin/JW/THEOplayer — you don't need Widevine |
| Networking | `URLSession` + `async/await` + `Codable` | Patreon's JSON:API surface is ~12 endpoints; hand-write a ~200-line JSON:API decoder |
| Auth storage | KeychainAccess | Modern wrapper over Security framework |
| Analytics | OSLog + Sentry (v1) → add TelemetryDeck later | **Skip Firebase** — its own README says tvOS is "official beta" |
| Testing | XCTest + ViewInspector + swift-snapshot-testing + Mocker | All declare tvOS, all active |
| Distribution | Xcode Cloud → TestFlight | Migrate to GH Actions + Fastlane if needed. Bitcode is dead as of Xcode 15 |

**Zero required external Swift dependencies at the start.** The reference app ships with none. Add Nuke + KeychainAccess when they earn their keep.

### 4.3 Companion stack

The reference app uses Swift (macOS-native). For a cross-platform companion (Mac + Linux/Docker), I'd propose:

- **Language: Go.** Fast, single-binary, easy cross-compilation, robust concurrency, tiny memory footprint on a Raspberry Pi.
- **HTTP framework: `chi`** (light router, stdlib-compatible).
- **Browser session capture:** `chromedp` (headless Chrome control) for the Linux companion; `WKWebView` on the Mac companion. Two implementations, same output (a `session_id` cookie + associated cookies).
- **Media proxy:** Go's `net/http` `ReverseProxy` with Range header pass-through.
- **`yt-dlp`:** subprocess (same as reference).
- **Storage:** SQLite (`modernc.org/sqlite`, pure-Go, no CGO).
- **Bonjour / mDNS:** `github.com/hashicorp/mdns`.

Alternative if you prefer JS: Node + Hono + Puppeteer + SQLite (`better-sqlite3`). Also works. Slightly heavier at runtime, slightly faster to develop.

I'd pick Go because a single 20MB static binary on a Raspberry Pi is a much better user experience than "install Node and Chromium."

### 4.4 The Netflix/Hulu-style UI (unchanged from earlier plan, still holds)

All previous polish targets apply. Home / Creator / Post / Player / Search / Discover / Library / Settings screens. Coordinated hero crossfades, focus tilt, preview-on-dwell. Nothing about the auth backend affects the UI stack.

The one UI adjustment: **the "sign in" screen becomes "pair with your companion,"** showing a Bonjour scan result or manual IP entry, plus a "your companion needs to be signed in to Patreon" hint that opens instructions.

## 5. Live testing plan (what we do now)

I've built a live-testing harness in `harness/` that runs the OAuth authorization-code flow and probes every relevant endpoint. **Given the research findings above, this harness is now less critical** — we already know the public API can't build the app. But it's still valuable to run because:

1. It confirms the exact shape of what the public API *does* return for a real fan account (for the Shape C fallback and for anything hybrid).
2. It confirms the exact scope grant behavior and the exact error shapes when a fan queries `campaigns.posts` on someone else's campaign.
3. It gives us a real bearer token we can use to test the *internal* API alongside the OAuth API and compare responses.

### 5.1 What I need from you to test

To run the OAuth harness, you need to:

1. **Register a V2 OAuth client** at https://www.patreon.com/portal/registration/register-clients
   - You'll need a Patreon *creator* account to do this (even for a consumer app — this is a documented Patreon requirement). If you don't have one, create one — you don't have to launch it.
   - Set the redirect URI to exactly: `http://localhost:8721/callback`
   - Choose V2 client type.
2. Send me (or paste into `harness/.env`):
   - `PATREON_CLIENT_ID`
   - `PATREON_CLIENT_SECRET`
3. Have on hand a Patreon fan account (can be your creator account too — it can be both) that supports at least **one** other creator. If you don't currently support anyone, pledge $1 to a small creator you like — we'll use their content for the probe. Cancel after if you want.
4. Optional but very valuable: if you know a creator personally who'd let you test with **their** OAuth authorization (they authorize our app against their campaign), we can see the full creator-side API surface — post shapes, media relationships, and confirm what the docs say about `campaigns.posts`.

### 5.2 What running the harness will show

- `dumps/fan/02-identity-full.json` — real shape of a fan's identity + memberships
- `dumps/fan/05-campaign-<id>-posts-DENIED.json` — exact error shape when a fan queries another creator's posts (to confirm/deny the "creator authorization" theory)
- `dumps/creator/10a-video-posts-summary.json` — if we have a creator test, what real video posts look like via the public API
- Rate-limit header behavior — the docs mention limits but not headers; we'll see what's actually sent

### 5.3 What we'd learn from the internal API (later, if we go Shape A)

Once we've built the companion, we should probe the internal API too — using a real session cookie in a test account. The community OpenAPI spec (`docs/patreon-internal-api-openapi.yaml`) is our starting map, but responses from real content will tell us:

- Actual URL shapes for Patreon-hosted video (`c10.patreon.com` CDN? signed how? expires how?)
- Whether HLS is used anywhere or if it's all progressive MP4
- Live streaming: is there a viewer-side playback URL, or is it purely a broadcast API for creators?
- Comment payloads (if we ever want to add comments)

## 6. What I need from you to move forward

**Three decisions, one action.**

### Decision 1 — Which product shape?

- **Shape A** (LAN companion, App Store possibly via reader-app exemption, definitely via sideload / TestFlight) — recommended
- **Shape C** (public API only, no video, catalog/reader app) — safe alternative
- **Shape B** (cloud service holding session cookies) — I'd like a clear "no" here so we can rule it out

### Decision 2 — Companion platform priority for v1?

- Mac only (fastest — matches the reference implementation exactly)
- Mac + Linux/Docker (better product, ~30% more work)

### Decision 3 — Are you OK with the internal API dependency?

If Shape A: the app depends on Patreon's undocumented internal API. Patreon has explicitly discouraged third-party use of it. It could break next Tuesday. Community projects have kept up with breakage for years now, but it's real risk. Comfortable proceeding?

### Action — Register the OAuth client and share the credentials

Even in Shape A, we may still want an OAuth path for the "identity + memberships" bootstrap (so the app knows who you are and which creators you nominally support without scraping). And it lets us do the Shape C fallback with the same codebase. Register the client, put creds in the harness `.env`, and I'll run the probe.

## 7. What I'm going to do next

Once you answer the questions above:

- **If Shape A:** I'll start by studying the reference app's code end-to-end and produce a fork plan — what we keep, what we replace, what we improve, plus a proper SwiftUI-first UI rewrite. The reference is functional but the UI is not Netflix-caliber; the *architecture* is. We can adopt architecture and rebuild UI.
- **If Shape C:** I'll build a proper OAuth device-pairing shim backend, and a much narrower tvOS app focused on the catalog/reader use case with best-in-class text-and-image polish.
- **Either way:** I'll run the OAuth harness with your credentials as a validation step and produce a "here's what the API actually returned" appendix so we have ground truth for the decisions ahead.

---

## Appendix — files in this workspace

```
patreon-tv/
├── PLAN.md                                     # this document
├── docs/
│   ├── patreon-api-docs.md                     # extracted official docs (source of truth)
│   ├── patreon-research.md                     # 1,185-line evidence-based research
│   ├── patreon-internal-api-openapi.yaml       # community-maintained internal-API spec
│   ├── library-research.md                     # 552-line library evaluation
│   └── portal-oauth.txt                        # Patreon's OAuth explainer page
├── harness/
│   ├── package.json
│   ├── .env.example                            # copy to .env and fill in creds
│   ├── auth-server.js                          # OAuth authorize + callback + token exchange
│   ├── probe.js                                # exercises every endpoint we care about
│   └── README.md
└── PatreonTV/                                  # reference tvOS app (MIT, kochj23)
    ├── PatreonTV/                              # tvOS app
    ├── PatreonTV Relay/                        # macOS companion
    ├── PatreonTV Top Shelf/                    # tvOS Top Shelf extension
    ├── Shared/                                 # shared models + API client
    └── ...
```

All research and code is ready for review.
