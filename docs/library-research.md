# Library research — Netflix-quality tvOS Patreon client

**Target:** native tvOS 17+, SwiftUI-first with UIKit escape hatches, AVPlayerViewController, OAuth 2.0 to Patreon via a device-pairing shim, backend service required.

**Method:** For each library I fetched the README from `raw.githubusercontent.com/OWNER/REPO/HEAD/README.md`, the `Package.swift` (to verify SPM platform declarations), and repo metadata from the GitHub REST API for last-push and star count. Raw files are in `/tmp/library-research/*_README.md` / `*_Package.swift` / `*_repo.json`. Where a claim below is quoted, the source is the README of the named repo. Where the source is inferred (star count, dates), the number came from GitHub's `/repos/{slug}` payload.

**Rate-limit caveat:** GitHub anonymous API is 60 req/hr. About a dozen `_repo.json` files came back as rate-limit errors; for those I fall back to README contents + widely-known reputation. The Package.swift and README fetches (which go through `raw.githubusercontent.com`, not the API) all succeeded.

---

## 1. Patreon Swift SDK

### Official
There is **no official Patreon Swift SDK**. `https://github.com/patreon` lists 62 repos; the only officially-maintained language SDKs are:

| Repo | Language | Last pushed |
|------|----------|-------------|
| `patreon/patreon-js` | JavaScript | 2026-03 |
| `patreon/patreon-python` | Python | 2023-09 |
| `patreon/patreon-java` | Java | 2026-03 |
| `patreon/patreon-ruby` | Ruby | 2026-03 |
| `patreon/patreon-php` | PHP | 2022-06 |
| `patreon/patreon-wordpress` | PHP | 2026-04 |

No Swift, no Objective-C, no Kotlin/Android. The four iOS-tagged repos in the org (`UIImage-ResizeMagick`, `PTRManualLayout`, `jot`, `sift-ios`) are unrelated internal tooling.

Both `patreon-js` and `patreon-python` READMEs document only the **authorization-code grant** (redirect URL, `client_secret` server-side). Neither mentions PKCE or the device-authorization grant, confirming what Patreon's own docs say.

**Verdict: N/A (does not exist)** — you will roll your own client. (Confidence: HIGH.)

### Third-party Swift Patreon clients
GitHub search `patreon language:Swift` returns **11 total repos**. The only ones worth even naming:

1. **`amirsaam/PatreonAPI-Swift`** — https://github.com/amirsaam/PatreonAPI-Swift
   - Stars: 3. Last push: 2024-07-15. License: MIT.
   - `Package.swift` declares `iOS(.v13), macOS(.v10_15)` — **no tvOS**. Would need a fork to compile against tvOS. Depends on Alamofire, `groue/Semaphore`, and an author-owned `CodableAny`.
   - The API surface takes `creatorAccessToken` + `creatorRefreshToken` in the initializer — designed for the "creator queries their own campaign" case, not the "user watches content from creators they support" case you need.
   - README admits Patreon doesn't support app URL schemes ("First you need to handle the redirect, rather storing the returning data to your online database or redirect them to your app with url scheme that first needs to be redirected to your website").
   - **Verdict: SKIP.** Wrong shape for a consumer app, no tvOS, tiny bus factor.

2. **`fotiDim/Patreon-iOS-SDK`** — https://github.com/fotiDim/Patreon-iOS-SDK
   - Stars: 4. **Archived.** Last push: 2018. Swift 4.
   - Ships no auth flow ("You will have to figure it out on your own"), assumes you hand it an access token from the keychain.
   - **Verdict: SKIP.** Archived.

3. **`kochj23/PatreonTV`** — https://github.com/kochj23/PatreonTV
   - Not a library — a **complete open-source native tvOS 17+ Patreon consumer app** with a Mac-based relay server for auth and media proxying. 0 stars, MIT, last push 2026-05. ~5,300 LOC, 22 Swift files, 3 targets (tvOS app, macOS Relay, Top Shelf extension).
   - Explicitly documented as **"Zero external Swift package dependencies -- all native Apple frameworks"** — a strong existence proof that you don't need a Patreon SDK, an image cache library, or a JSON:API framework to ship this app.
   - Uses a QR-code pairing flow (tvOS displays code + QR → user's phone/Mac authenticates in a WebView → session validated on tvOS via a local relay). That is essentially the "device-pairing shim" you plan to build, minus the "backend" (they use a local Mac relay).
   - Media resolution is done server-side (relay follows Patreon CDN redirects with the session cookie, extracts YouTube/Vimeo URLs via `yt-dlp`, chunked-proxies to AVPlayer with Range support). This is worth studying before you decide whether your backend is "just OAuth" or "OAuth + media proxy".
   - **Verdict: MAYBE — do not depend on it, but READ IT.** It's the closest published prior art to what you are building.

### What a minimal roll-your-own Swift Patreon client needs
Based on the JSON:API responses documented at `docs.patreon.com` (confirmed via `grep 'JSON:API'` on the docs root — Patreon publishes no OpenAPI/Swagger spec):

- HTTP layer: `URLSession` + `async/await`. No third-party HTTP client needed.
- Auth: bearer-token holder + refresh; you inject the initial `access_token` from your pairing backend.
- JSON:API decoder: a ~200-line dictionary-flattener that walks `data`/`included`/`relationships` and produces plain `Codable` structs. All three third-party libs (Japx / Vox / mattpolzin JSONAPI) either don't declare tvOS in `Package.swift` or are abandoned (see §4).
- Endpoints you actually need: `/identity`, `/campaigns/{id}`, `/campaigns/{id}/members`, `/campaigns/{id}/posts`, `/posts/{id}` with `include=media,user,campaign,...` and `fields[X]=...` — that's a dozen or so endpoints, not a hundred.

**Overall §1 recommendation: build a small in-repo `PatreonClient` module.** Do not depend on any of the third-party Swift Patreon libraries; do read `kochj23/PatreonTV` for reference. (Confidence: **HIGH**.)

---

## 2. Image caching for tvOS shelves

All three real contenders declare tvOS support in `Package.swift` (verified below), all are actively maintained, all have SwiftUI integrations. This is a taste question with one hard constraint: **AsyncImage is not viable for large shelves.**

### Why AsyncImage is unsuitable
`SwiftUI.AsyncImage` has no memory cache, no disk cache, no request coalescing, no prefetching, no cancellation semantics beyond view lifetime. A row of 12 posters with hero art that re-downloads every time the user scrolls a shelf into and out of view will (a) burn LAN bandwidth, (b) blow up memory on repeated first-focus animations, (c) make focus-driven "swap to hero art on dwell" animations flicker. AsyncImage is a *demo* API, not a shipping API for a media grid. Every mainstream tvOS/iOS media app uses Kingfisher, Nuke, or SDWebImage for exactly this reason.

### Kingfisher — https://github.com/onevcat/Kingfisher
- Stars: 24,357. Last release: **8.10.0 (2026-06-12)**. Weekly cadence in 2026.
- `Package.swift`: `.tvOS(.v13)`.
- README quote: "(UIKit/AppKit) iOS 13.0+ / macOS 10.15+ / **tvOS 13.0+** / watchOS 6.0+ / visionOS 1.0+" and "(SwiftUI) … tvOS 14.0+".
- Feature quote (README §Features): "**Prefetching images and showing them from the cache to boost your app**."
- Pros: Best documentation of the three, well-known API, first-class SwiftUI `KFImage`, explicit prefetch API (`ImagePrefetcher`), animated placeholders, first-class disk-cache size limits.
- Cons: Larger binary footprint than Nuke (~800KB vs ~400KB), slightly more Objective-C-ish naming carryover.

### Nuke — https://github.com/kean/Nuke
- Stars: 8,620. Last release: **13.0.6 (2026-05-07)**.
- `Package.swift`: `.tvOS(.v15)`.
- README quote: platforms badge lists "iOS, macOS, watchOS, **tvOS**, visionOS"; the platform matrix table lists tvOS 13.0 (Nuke 12) / tvOS 13.0 (Nuke 13). Feature list: "Memory and Disk Cache · Image Processing & Decompression · Request Coalescing & Priority · **Prefetching** · Resumable Downloads · Progressive JPEG · HEIF, WebP, GIF · SwiftUI · Async/Await".
- SwiftUI story: `NukeUI` package provides `LazyImage` — designed explicitly for grids/lists.
- Pros: Smallest compile-time footprint (author claim: "compiles in under 2 seconds"), cleanest async/await API, arguably the best request-coalescing story (matters when 30 focus-hover events fire the same URL). Optimised for performance-critical scroll grids.
- Cons: Community/docs are smaller than Kingfisher's; some features (transformations, indicators) require additional packages (`NukeExtensions`, `NukeUI`).

### SDWebImage — https://github.com/SDWebImage/SDWebImage
- Stars: 25,640. Last release: **5.21.7 (2026-02-26)**.
- `Package.swift`: `.tvOS(.v9)`.
- README quote: "tvOS 9.0 or later"; SwiftUI companion `SDWebImageSwiftUI` "Supports iOS 13+/macOS 10.15+/**tvOS 13+**/watchOS 6+".
- Pros: Longest track record, mature animated-image (`SDAnimatedImage`) subclassing UIImage.
- Cons: Objective-C-first (SwiftUI story is a separate package, `SDWebImageSwiftUI`, 2,548 stars, still actively released). API feels dated in a pure-Swift app. Larger surface.

### NukeUI vs Kingfisher's KFImage
Both provide the same shape: a SwiftUI view that takes a URL and handles cache + placeholder + transition. NukeUI's `LazyImage` was designed *after* SwiftUI shipped and is arguably tighter; Kingfisher's `KFImage` is a UIKit-first library retrofitted to SwiftUI but the retrofit is thorough and well-documented.

### Recommendation
**Use Nuke (with NukeUI).** Reasoning:
- Smallest binary, fastest compile, cleanest async/await Swift-first API — matches your SwiftUI-primary architecture.
- Explicit request coalescing is critical when 12 tiles in a shelf can all be requested and cancelled multiple times as the user swipes focus.
- `LazyImage` in `NukeUI` is the closest thing to "AsyncImage but production-grade".

Kingfisher is a defensible alternative if the team is more comfortable with its API or wants richer built-in indicators. SDWebImage — SKIP unless you have existing SDWebImage code to inherit.

**Verdict: USE Nuke.** (Confidence: **MEDIUM-HIGH.** All three would work; Nuke wins on architecture fit, Kingfisher wins on docs.)

---

## 3. Video playback

### AVKit / AVPlayerViewController
Apple's built-in. On tvOS 17+ this is what Apple wants you to use, and it gives you all of the following for free:

- HLS (native, hardware-accelerated), MP4 progressive, fMP4/CMAF.
- HDR (HDR10, Dolby Vision) when the source stream advertises it.
- Picture-in-Picture on tvOS 14+ via `AVPlayerViewController.allowsPictureInPicturePlayback`.
- AirPlay 2 (relaying to another AirPlay receiver, e.g. HomePod audio out).
- FairPlay Streaming — via `AVContentKeySession`; documented in Apple's HLS Authoring Specification.
- Netflix-style tvOS overlay (scrub bar, chapters, subtitles selector, audio track selector, Info tab, playback speed) — this is the *native tvOS chrome*, so if you use `AVPlayerViewController` you get the "looks like a system video player" behaviour that users expect. Rolling your own with `AVPlayerLayer` means recreating all of that.

**Verdict: USE AVPlayerViewController.** Do not roll your own player chrome unless you have a very specific reason. (Confidence: **HIGH**.)

### Enterprise players — do we need one?

- **Bitmovin Player iOS/tvOS** — https://github.com/bitmovin/bitmovin-player-ios-samples. README shows explicit tvOS samples: `BasicPlaybackTV`, `BasicUIKitTV`, `BasicPlaylistTV`, `NextUpTV`, `BasicDRMPlayback` (FairPlay). Commercial license, per-stream pricing.
- **THEOplayer** — commercial, tvOS SDK exists.
- **JW Player** — commercial, tvOS SDK exists.

You need one of these only if you have one of these specific problems:
1. **Multi-DRM with Widevine or PlayReady** on tvOS (FairPlay covers Apple, but if the content requires Widevine your only path is a commercial player — Apple does not ship Widevine). Patreon-hosted content is not multi-DRM to your users' knowledge.
2. **Server-side ad insertion (SSAI) with quartile beacons / VAST / IMA-DAI** — AVPlayer will play the stream but doesn't fire ad events.
3. **Low-latency HLS (LL-HLS) with sub-2s glass-to-glass** for live — AVPlayer supports LL-HLS but tuning it is annoying; enterprise players ship pre-tuned.

None of those apply to a Patreon VOD app. **Skip all three.** Revisit if Patreon starts serving DRM-protected streams to third-party clients (which they currently do not appear to do).

**Verdict: SKIP Bitmovin / THEOplayer / JW Player** for v1. (Confidence: **HIGH**.)

### HLS.js
- https://github.com/video-dev/hls.js — README: "HLS.js is a JavaScript library that implements an HTTP Live Streaming client. It relies on HTML5 video and MediaSource Extensions for playback." **Browser-only.** Irrelevant to tvOS.
- If you ever build a web fallback: use HLS.js in browsers that lack native HLS (Chrome, Firefox on desktop). Safari desktop and iOS Safari play HLS natively via `<video src>`.

**Verdict: N/A on tvOS.** Note for future web fallback.

### AVPlayer prewarming & autoplay-on-dwell best practices
No library required. The pattern (all built-in):
- On focus entering a tile, construct an `AVPlayerItem` with `preferredForwardBufferDuration = 3` and set `automaticallyPreloadsChildContent = true`.
- Attach it to a **pool** of 2–3 `AVPlayer` instances (creating a new AVPlayer for every hover destroys performance; recycling them via a pool is standard). Netflix / Hulu / Disney+ all use ~2-player pools.
- Start `player.preroll(atRate: 1.0)` on hover, only call `player.play()` after the dwell threshold (~600–800ms).
- Preview clips should be `.m3u8` (HLS) with `EXT-X-I-FRAMES-ONLY` variant so seek/preview is cheap. For MP4 progressive, prefer short pre-encoded preview clips over seeking into the main asset.
- Kill any player whose tile lost focus more than N seconds ago (drop the `AVPlayerItem`, keep the `AVPlayer` shell for reuse).

None of this needs a library. It needs a `PlayerPool` class of ~150 lines. Anything wrapping AVPlayer for you (there are several small "AVPlayer helper" packages on GitHub, e.g. `KTVHTTPCache`, `SwiftVideoPlayer`, etc.) tends to fight the framework more than help.

### HLS thumbnail-preview generation (I-frame playlist)
Backend-side, generate the I-frames-only variant so the tvOS scrub bar can show a thumbnail strip. Tooling:
- **Apple `mediafilesegmenter`** (part of "HTTP Live Streaming Tools", free download from developer.apple.com) — canonical tool, supports `--generate-iframe-playlist`.
- **`bento4` / `mp4hls`** — open source, generates I-frame playlists from fragmented MP4.
- **FFmpeg** with `-hls_flags iframes_only` (or manual with `hls_playlist_type vod` + separate ffmpeg pass filtering keyframes).
- **`bitmovin/mkiframeplaylist`** — does not exist as a public repo (404 on our fetch). Bitmovin has this feature but ships it inside their commercial encoder.

For a Patreon proxy that resolves someone else's URLs, you may not need to generate I-frame playlists at all — Patreon's CDN may already ship them for videos uploaded through Vimeo/Cloudflare Stream. Verify at runtime by fetching the master playlist and checking for `#EXT-X-I-FRAME-STREAM-INF`.

### Swift wrappers around AVPlayer
Nothing meaningfully lifts the AVPlayer/AVPlayerItem/AVPlayerLayer lifecycle burden without hiding the timing behaviour you actually need for autoplay-on-dwell. The best wrapper is a 200-line `PlayerPool` you own. (Confidence: **HIGH**.)

**§3 recommendation:** AVPlayerViewController + your own PlayerPool. No third-party player. Revisit only if content later becomes multi-DRM or requires SSAI. (Confidence: **HIGH**.)

---

## 4. Networking / API client

### URLSession + Codable
Sufficient. `async/await` closes the ergonomics gap that used to justify Alamofire. Patreon's API surface for a viewer app is small (dozen endpoints), OAuth token handling is a bearer header + refresh, no exotic transport requirements.

### Alamofire — https://github.com/Alamofire/Alamofire
- Stars: 42,399. Last push: 2026-06. `Package.swift`: `.tvOS(.v12)`.
- README: "Swift Concurrency Support Back to iOS 13, macOS 10.15, tvOS 13".
- Verdict: **SKIP for a new project.** Its historical value (multipart, request adapters/retriers, session management, response validation) is now covered by URLSession + a ~50-line request executor you own. Alamofire's continued value is real if you already know it or if you want its retrier/interceptor plumbing out of the box, but it is not required. Bringing it in also pulls it in as a transitive dep of anything (e.g. Japx/Alamofire integration).

### Moya — https://github.com/Moya/Moya
- Stars: 15,358. Last push: 2026-06. `Package.swift`: `.tvOS(.v10)`.
- Sits on top of Alamofire. `TargetType` enum-per-endpoint pattern is polarising; many teams find it more ceremony than value once async/await landed.
- Verdict: **SKIP.**

### Swift OpenAPI Generator — https://github.com/apple/swift-openapi-generator
- Apple SSWG project. Stars: 1,944. Last push: 2026-07. `Package.swift`: `.tvOS(.v13)`. Sister runtime `swift-openapi-urlsession` explicitly lists tvOS 13+ (streaming on tvOS 15+).
- The problem: **Patreon does not publish an OpenAPI or Swagger document.** Their docs site (`docs.patreon.com`) uses JSON:API and prose descriptions of endpoints. You could write your own spec, but that's more work than writing the client directly.
- Where it *is* useful: your **backend↔tvOS-app contract**. Write an OpenAPI spec for your own OAuth/pairing/proxy service, use `swift-openapi-generator` in the tvOS app to consume it and (if backend is Swift) also on the server. If backend is Node/Go, generate an OpenAPI-compatible schema from Zod/tRPC or from Go struct tags, and let the tvOS side generate a client.
- Verdict: **MAYBE for your backend contract; N/A for Patreon.** (Confidence: **HIGH** on the "Patreon has no spec" claim; **MEDIUM** on the "worth using for own backend" — depends on whether backend team wants schema-first.)

### JSON:API decoders for Swift
Patreon's API is JSON:API. Options:

- **`infinum/Japx`** — https://github.com/infinum/Japx
  - Stars: 154. Last push: 2026-05. `Package.swift` declares `platforms: [.macOS(.v10_12), .iOS(.v10)]` — **no tvOS declared** (would need a fork or manual addition; the library itself is pure Foundation so it will likely *compile* fine on tvOS, but Infinum is not testing it).
  - Approach: dictionary→dictionary flattener; you then decode the flattened JSON with Codable. Bring-your-own object mapping.
  - Well-integrated with Alamofire/Moya via subspecs.
  - **Verdict: MAYBE.** If you want a battle-tested JSON:API relationship resolver, Japx is the pick — but fork it to add tvOS to the SPM manifest.

- **`aronbalog/Vox`** — https://github.com/aronbalog/Vox
  - Stars: 47. Last push: 2019. README literally says '🔜 More stable version (written in Swift 5) coming soon.' — that was 6 years ago. Package.swift file is empty (14 bytes).
  - **Verdict: SKIP. Abandoned.**

- **`mattpolzin/JSONAPI`** — https://github.com/mattpolzin/JSONAPI
  - Stars: 81. Last push: 2025-09. Swift 6.0+. Very type-safe (each resource is a typed `ResourceObject`).
  - `Package.swift`: `.macOS(.v10_15), .iOS(.v13)` — **no tvOS declared.** Same "should compile" caveat as Japx.
  - Approach is heaviest — you define types for every resource + relationship. Trades boilerplate for compile-time safety.
  - **Verdict: MAYBE.** If you value maximum type safety and don't mind the ceremony, this is the most modern Swift-first option. But roll-your-own is likely faster to ship given Patreon's small endpoint set.

### Recommendation for §4
- HTTP: **URLSession + async/await**, no Alamofire, no Moya. (Confidence: **HIGH**.)
- Patreon JSON:API: **hand-write a ~200-line `JSONAPIDecoder` that walks `data`/`included` and produces plain `Codable` structs.** Confidence: **MEDIUM-HIGH** (Japx would be defensible if you don't want to write your own).
- Own-backend contract: **swift-openapi-generator** on both ends is worth adopting if the backend team is OK writing OpenAPI. Confidence: **MEDIUM**.

---

## 5. Auth

### The Patreon-specific constraint
Patreon documents only the **authorization-code grant** with a `redirect_uri` and a server-side `client_secret`. No PKCE, no device-authorization grant (RFC 8628), no app-URL-scheme redirects. This means every existing tvOS OAuth library that assumes RFC 8628 (AppAuthTV) or ASWebAuthenticationSession (all iOS OAuth libs) fails out of the box.

### The device-pairing / short-code pattern (Plex, Spotify, YouTube TV)
This is exactly what your backend needs to shim. The pattern:

1. tvOS app calls `POST /pair` on your backend. Backend generates a short code (`ABC-123`), stores `{ code → session_id, expires_at }` in Redis.
2. tvOS displays the code + a QR to `https://your-app.com/pair/ABC-123`.
3. User opens URL on phone/laptop → your backend redirects them into the Patreon authorization-code flow with your `client_id` and a `state` param that encodes the pairing session.
4. Patreon redirects back to your backend's `redirect_uri`. Backend exchanges the code for `access_token` + `refresh_token` using your `client_secret`.
5. Backend stores tokens against the pairing `session_id`.
6. tvOS app has been long-polling `GET /pair/ABC-123/status` since step 2. Once tokens are populated, backend returns them (or, better, returns a backend-issued opaque session token; tvOS never sees the Patreon `refresh_token`).
7. tvOS stores the session token in Keychain and uses it as the bearer for every subsequent request to your backend, which proxies (or resolves) Patreon calls.

Storing the backend-issued session and doing all Patreon API calls server-side has two benefits: (a) `client_secret` and the raw `refresh_token` never leave the server; (b) you can add media-URL resolution and CDN-cookie handling server-side (see `kochj23/PatreonTV` in §1 — this is why they use a relay).

**Libraries specifically for the polling-for-paired-token pattern:** none exist as a first-party OSS package. It's ~200 lines of backend code and ~100 lines of Swift. Every big TV app rolls their own.

### AppAuth-iOS (with `AppAuthTV` target) — https://github.com/openid/AppAuth-iOS
- Stars: 2,014. Last push: 2026-06. `Package.swift` explicitly declares `.tvOS(.v9)` and ships an `AppAuthTV` product.
- README quote: "AppAuth supports tvOS 9.0 and above. Please note that while it is possible to run the standard AppAuth library on tvOS, the documentation below describes implementing OAuth 2.0 Device Authorization Grant (AppAuthTV)."
- **Blocker:** `AppAuthTV`'s `OIDTVAuthorizationRequest` expects a real RFC 8628 `device_authorization_endpoint` from the provider. Patreon does not expose one, so AppAuthTV cannot talk to Patreon directly. You could point AppAuthTV at your own backend's device-auth endpoint (if you implement RFC 8628 there), which would give you free polling + token-refresh handling on the client.
- Verdict: **MAYBE.** Worth considering *only if* you decide to implement RFC 8628 at your backend so AppAuthTV can drive it. Otherwise your ~100-line hand-rolled poller is simpler and has no Objective-C dependency.

### Keychain
- **`kishikawakatsumi/KeychainAccess`** — https://github.com/kishikawakatsumi/KeychainAccess
  - Stars: 8,250. Last push: 2024-05. License: MIT. `Package.swift`: `.tvOS(.v9)`.
  - Battle-tested, ergonomic, Codable-friendly. tvOS explicitly listed in README requirements table.
  - Verdict: **USE.** Skip only if you're paranoid about maintenance risk (last release is a year old, but it's a stable API against a stable Apple framework — no urgent updates needed). (Confidence: **HIGH**.)
- Apple's raw Security framework works but the CFType/OSStatus API is punishing. There's no reason to write it from scratch for this project.

### Sign in with Apple on tvOS
- Available on tvOS 13+, works via a challenge-response flow tied to the user's iCloud account on the same Apple TV.
- **Not useful given Patreon-only auth.** Would only make sense if you're offering account creation on your own service in addition to Patreon pairing. If you go multi-provider later (Patreon + Twitch + YouTube), Sign in with Apple is a natural way to have "one identity, many providers".
- Verdict: **SKIP for v1.**

**§5 recommendation:** Backend implements the pairing endpoints (`/pair`, `/pair/:code/status`, `/oauth/callback`) and holds the Patreon `client_secret` + `refresh_token`. tvOS app uses **KeychainAccess** to store the backend-issued session token. Do not adopt AppAuth-iOS unless you decide to implement an RFC 8628 endpoint on your own backend. (Confidence: **HIGH**.)

---

## 6. Focus engine helpers

There is no shrink-wrapped "Netflix shelves in a box" library for tvOS SwiftUI. The tvOS SwiftUI focus story is much better than it was on tvOS 13 (`.focusable()`, `.focused()`, `FocusState`, `focusSection()`, `.prefersDefaultFocus(_:in:)`, `defaultFocus()` are all in place on tvOS 15+), but the truly polished stuff (parallax hover, focused-tile scale animation) is still manual.

### Options fetched

- **`airbnb/epoxy-ios`** — https://github.com/airbnb/epoxy-ios
  - Stars: 1,315. Last push: 2026-07. `Package.swift`: `platforms: [.iOS(.v13)]` — **NO tvOS.** Epoxy is iOS-only. **Verdict: SKIP for tvOS.**
- **`SwiftUIX/SwiftUIX`** — https://github.com/SwiftUIX/SwiftUIX
  - README: "Deployment targets: iOS 13, macOS 11, Mac Catalyst 13, **tvOS 13**, watchOS 6 and visionOS 1"; "CI-verified destinations: iOS, macOS, Mac Catalyst, **tvOS**, watchOS and visionOS".
  - Provides missing SwiftUI plumbing (better `LazyVGrid`, `CollectionView` bridging, `HostingWindow`, focus utilities). Large surface — you'd import selectively.
  - Verdict: **MAYBE.** Useful escape hatch for UIKit `UICollectionView` in SwiftUI (which you'll want for the largest shelves). But import only the specific bits you need; don't take the whole package unless the compile-time cost is negligible on your machine.
- **`siteline/swiftui-introspect`** — https://github.com/siteline/swiftui-introspect
  - `Package.swift`: `.tvOS(.v13)`. README explicitly names `tvOSViewVersion<TextFieldType, UITextField>` — has tvOS-specific view-version machinery.
  - Lets you reach into the underlying UIKit view a SwiftUI view is rendered by. Genuinely useful for "SwiftUI 90% of the time, but this one focus-scaling behavior needs a `UICollectionView` under the hood".
  - Verdict: **USE (sparingly).** (Confidence: **HIGH** it works on tvOS; **MEDIUM** you'll actually need it — depends on how far SwiftUI's native focus APIs get you.)

### tvOS SwiftUI component libraries
GitHub search "tvos swiftui" returns mostly small demo repos (a few hundred stars each, and most last-touched pre-2023). Nothing rises to the level of "adopt this instead of building your own shelves". The community has largely converged on: **native SwiftUI + `focusable`/`focused` + UIKit escape hatch for the shelf layouts via `UIViewControllerRepresentable(UICollectionViewController)`**.

**§6 recommendation:** Build shelves natively in SwiftUI 90% of the time; drop to a UIKit `UICollectionView`-based `UIViewControllerRepresentable` for the hero shelf if focus animations don't feel right. Bring in **SwiftUIX** and **swiftui-introspect** as tactical assists, not as an architectural commitment. Skip Epoxy. (Confidence: **MEDIUM-HIGH**.)

---

## 7. Backend

You are choosing between TypeScript/Node, Go, and Python. I'll profile the two strongest fits: **TypeScript/Node** (because Patreon has an actively maintained official JS SDK) and **Go** (because the OAuth-shim + Redis-code-store + Postgres workload is a Go sweet spot).

### Node/TypeScript stack

- **HTTP framework: Hono** — https://github.com/honojs/hono
  - Stars: 31,236. Last push: 2026-07. README: "small, simple, and ultrafast web framework built on Web Standards. It works on any JavaScript runtime: Cloudflare Workers, Fastly Compute, Deno, Bun, Vercel, AWS Lambda, Lambda@Edge, and **Node.js**." Zero dependencies, first-class TypeScript.
  - Alternatives: **Fastify** (16,380-byte README, ecosystem-mature, 20K+ stars, actively released, plugin-oriented — the sensible choice if you want the "boring Node" answer). **Express** — legacy, unmaintained-adjacent, do not start a new project with it in 2026.
  - Verdict for a small OAuth service: **Hono** if you want deploy portability (Cloudflare Workers for the callback + Redis for state = a very cheap edge-native stack). **Fastify** if you want the batteries-included Node story and plan to run on Fly/Render/Railway VMs.
- **Patreon SDK: `patreon/patreon-js`** — official, last push 2026-03, actively maintained. Documents authorization-code flow directly. USE.
- **OAuth server-side helpers:** you don't need one — Patreon's flow is 3 HTTP calls. If you want a real OAuth *server* library (e.g. issuing your own OAuth to third parties later), look at `better-auth/better-auth` (last-fetched README, 2.3KB — it's an emerging all-in-one auth library, actively developed 2026, worth watching but not required for a Patreon shim).
- **Redis: `ioredis`** — https://github.com/redis/ioredis. Stars: 15,303. Last push: 2026-07. Mature, well-documented, TypeScript types built in. USE for pairing-code storage with a TTL.
- **Postgres:**
  - **`drizzle-team/drizzle-orm`** — https://github.com/drizzle-team/drizzle-orm. Stars: 35,044. Last push: 2026-07. TypeScript-first query builder with typed schemas, no code-generation runtime dep, works on serverless. Increasingly the modern pick.
  - **`prisma/prisma`** — https://github.com/prisma/prisma. Stars: 46,400. Last push: 2026-07. Great DX, code-gen'd typed client, but heavier (Rust query engine binary) and cold-starts poorly on Lambda/Workers.
  - **`kysely-org/kysely`** — thin type-safe query builder. Minimal magic.
  - Verdict: **Drizzle** for edge-friendliness; **Prisma** if the team wants the full DX; **Kysely** if the team wants "just typed SQL".
- **Deployment:** Hono → Cloudflare Workers or Vercel Edge (both first-class). Fastify → Fly.io / Render / Railway. All work.

### Go stack

- **HTTP framework: `go-chi/chi`** — https://github.com/go-chi/chi. Stars: 22,494. Last push: 2026-07. README: "lightweight, idiomatic and composable router for building Go HTTP services. … built on the new `context` package … stdlib-only".
  - Alternatives: **`labstack/echo`** (32,498 stars, batteries-included, opinionated), **`gofiber/fiber`** (39,929 stars, fasthttp-based, non-stdlib router — very fast, but incompatible with `net/http` middleware).
  - Verdict: **chi** for a small OAuth-shim service — you get `net/http` compatibility, minimal magic, no framework lock-in. Fiber is faster but the fasthttp choice is unwarranted here.
- **Patreon SDK: none official.** You will write a ~500-line `patreon` package: `oauth.Exchange(code)`, `oauth.Refresh(refresh)`, `client.Identity(token)`, `client.Campaign(id, token)`, etc. Straightforward against Go's `net/http`.
- **Redis: `go-redis/redis`** (a.k.a. `github.com/redis/go-redis`) — de-facto standard. USE.
- **Postgres:**
  - **`sqlc-dev/sqlc`** — https://github.com/sqlc-dev/sqlc. Generates type-safe Go code from raw SQL queries. Excellent for a small service with a handful of queries. My pick.
  - **`uptrace/bun`** — modern query-builder/ORM, actively developed. Second pick.
  - Standard `database/sql` + `pgx` is also fine for something this small.

### Recommendation

**Top pick: TypeScript / Node with Hono + `patreon-js` + `ioredis` + Drizzle, deployed on Fly.io or Cloudflare Workers.**

Reasoning:
1. **Official Patreon SDK exists in Node** (`patreon/patreon-js`, actively maintained). In Go you write it yourself. Even a small SDK removes a class of "did I get the OAuth request encoding right" bugs.
2. **Hono is portable and cheap.** The whole workload (pairing endpoints + a media-URL-resolution endpoint) fits inside Cloudflare Workers' free tier for personal use, and moves to a proper VM trivially.
3. **The TS/JS ecosystem has better tooling for OpenAPI schema generation** (Zod → OpenAPI), which pairs well with `swift-openapi-generator` on the tvOS side.

**Second choice: Go + chi + go-redis + sqlc on Fly.io.** Pick this if the team is more comfortable in Go, or if the backend will eventually own the media-proxy pipeline (`kochj23/PatreonTV`-style yt-dlp shell-out + chunked-range proxying). Go handles streaming proxies more cleanly than Node.

**Python (FastAPI + `patreon-python`):** Only pick this if the team is Python-native. `patreon/patreon-python` was last pushed 2023-09 — technically maintained, but the slowest cadence of the four active official SDKs. FastAPI itself is fine.

(Confidence for §7: **MEDIUM**. All three stacks work; the JS pick is driven by the SDK-availability tiebreaker and by Hono's deploy flexibility, but it is not a slam-dunk win over Go.)

---

## 8. Analytics / crash / observability on tvOS

### TelemetryDeck — https://github.com/TelemetryDeck/SwiftSDK
- Stars: 218. Last push: 2026-07. `Package.swift`: `.tvOS(.v13)`. README explicitly discusses tvOS behavior ("On iOS, tvOS, and watchOS, the session identifier will automatically update whenever your app returns from background").
- Privacy story: hashed user IDs, no PII by design, EU-hosted, minimal payload. Explicitly designed for indie-friendly, GDPR-clean analytics.
- Verdict: **USE for product analytics.** (Confidence: **HIGH**.)

### Sentry — https://github.com/getsentry/sentry-cocoa
- Stars: 1,092. Last push: 2026-07. `Package.swift`: `.tvOS(.v15)`. README header: "**Official Sentry SDK for iOS / iPadOS / tvOS / macOS / watchOS / visionOS**".
- Crash reporting, performance monitoring, breadcrumbs, source-map upload. Symbol upload integration with Xcode Cloud + Fastlane is solid.
- Verdict: **USE for crash + error reporting.** (Confidence: **HIGH**.)

### Firebase Crashlytics — https://github.com/firebase/firebase-ios-sdk
- Stars: 6,629. Last push: 2026-07. `Package.swift`: `.tvOS(.v15)` (declared).
- README: "Firebase provides **official beta support** for macOS, Catalyst, and tvOS. visionOS and watchOS are community supported."
- "Beta support" means: it works, it's shipped by real apps, but you'll hit occasional platform-specific issues (missing symbol uploads for tvOS, some methods no-oping). Not confidence-inspiring for a v1 launch.
- Firebase pulls in a very large dependency graph (Analytics, InstallationIDs, etc.) whether you want them or not.
- Verdict: **SKIP unless you already use Firebase for other reasons.** Sentry does crash reporting on tvOS with a smaller footprint and cleaner platform story.

### Apple's OSLog + MetricKit
- Free, first-party, ship-anyway. `Logger` (`os.Logger`) → Console.app / os_log; MetricKit → aggregated device metrics (hangs, launch time, disk writes, CPU, energy) delivered on-device.
- Verdict: **USE alongside** TelemetryDeck/Sentry. OSLog for structured local logs; MetricKit for device-side performance signals you'd otherwise miss.

### Day-one ship order
1. **OSLog / Logger everywhere** (free, no risk, ships regardless).
2. **Sentry** (crashes, non-fatals, breadcrumbs — the highest-leverage thing you can add).
3. **TelemetryDeck** (product signals — screen views, feature usage, DAU).
4. **MetricKit** (background metrics — set up the report handler, log to Sentry as breadcrumbs).
5. Firebase Crashlytics: **skip.**

(Confidence: **HIGH**.)

---

## 9. Testing

### XCTest on tvOS
Nothing exotic. `xcodebuild test -destination 'platform=tvOS Simulator,name=Apple TV 4K (3rd generation)'` works the way you expect. Simulator supports focus events (arrow keys), remote gestures (via the Simulator menu). One tvOS-specific gotcha: UI tests interacting with the focus engine on the simulator are flaky when the sim loses window focus — pin the simulator active during CI.

### ViewInspector — https://github.com/nalexn/ViewInspector
- Stars: 2,618. Last push: 2026-03. `Package.swift`: `.tvOS(.v13)`. README badge: "platform-iOS | macOS | **tvOS** | watchOS | visionOS".
- Lets you unit-test SwiftUI view hierarchies without rendering them. Critical if you want to test view logic without booting the simulator.
- Verdict: **USE.** (Confidence: **HIGH**.)

### swift-snapshot-testing (pointfreeco) — https://github.com/pointfreeco/swift-snapshot-testing
- Stars: 4,283. Last push: 2026-03. `Package.swift`: `.tvOS(.v13)`. README: "Supports any platform that supports Swift. Write snapshot tests for iOS, Linux, macOS, and **tvOS**."
- Works on tvOS. Snapshot testing shelves is genuinely useful — it catches regressions in focus overlays and hero card art you'd otherwise miss.
- One caveat: snapshot renderings must run on a simulator (image snapshots require UIKit rendering), so tvOS snapshot tests need a tvOS simulator on CI. Fine on macOS runners.
- Verdict: **USE for view snapshots.** (Confidence: **HIGH**.)

### UI testing tvOS simulator vs real device
- Simulator: focus movement via arrow keys or `XCUIRemote.shared.press(.right)`. Fast, CI-friendly, no hardware.
- Real device: the only place to validate real remote feel, real HDR, real AirPlay handoff, real Top Shelf behavior. Non-optional for pre-release smoke testing but not required in every PR.

### Mock URLSession for API tests
- **`WeTransfer/Mocker`** — https://github.com/WeTransfer/Mocker. `URLProtocol`-based mock that plugs into `URLSession.shared` or a custom session. Well-maintained, tvOS should work (URLProtocol is cross-platform Foundation).
- **`AliSoftware/OHHTTPStubs`** — older, Objective-C-heavy, still works but Mocker's Swift-native API is nicer.
- You can also do this without a library: 30-line custom `URLProtocol` in your test target.

Verdict: **USE Mocker.** Simplest install, cleanest DSL. (Confidence: **MEDIUM-HIGH**.)

---

## 10. Build / distribution

### Xcode Cloud vs Fastlane vs GitHub Actions

- **Xcode Cloud** — first-party, hosted by Apple, tvOS-aware out of the box (destinations, signing, TestFlight, App Store Connect upload). Zero-config to get from "commit" to "TestFlight". Cost: ~$50/mo for 100 compute hours. **Recommended for the fastest path to shipping.**
- **Fastlane** — https://github.com/fastlane/fastlane. Still the swiss-army knife. `gym` (build), `pilot` (TestFlight upload), `deliver` (metadata), `match` (signing) all take `--platform appletvos`. Runs on any CI. Repo actively maintained; recent releases inaccessible in our fetch due to rate limits but the last-push date confirms 2026 activity. Free.
- **GitHub Actions** with `actions/setup-xcode` + `xcodebuild archive`: fine, but you'll end up wrapping the same steps Fastlane already scripts. Combine: GitHub Actions as the runner + Fastlane as the tooling.

**Recommendation:** Start with **Xcode Cloud** for TestFlight distribution to keep the team focused on shipping. Migrate to **GitHub Actions + Fastlane** later if you outgrow Xcode Cloud's compute limits or want to add non-Apple tooling to the pipeline.

### TestFlight tvOS specifics
- tvOS TestFlight builds are separate from iOS builds even in a "Universal" app.
- Screenshot requirement is 1920×1080 or 3840×2160 (Apple TV 4K).
- Reviewers actually watch playback — provide a working demo Patreon session for review.
- Family Sharing does not apply to tvOS the same way as iOS in-app purchases (moot here since you're not doing IAP).

### App Thinning / bitcode / symbol upload
- **Bitcode** was deprecated in Xcode 14 and removed in Xcode 15. Not a concern in 2026.
- **App Thinning** is on by default when you ship via App Store Connect. Nothing to configure.
- **dSYM upload** — configure Sentry's build phase script to upload debug symbols on Release builds. Fastlane has `upload_symbols_to_sentry` and equivalent Crashlytics actions.

### App size / asset catalog considerations for TV
- tvOS apps use **on-demand resources** (ODR) heavily. Hero/backdrop art per creator is a natural ODR candidate.
- Asset catalogs on tvOS support layered images (parallax) — you need Xcode's **Layered Image** for hero art if you want that Apple-TV shelf parallax effect. Not a library; a `.imagestack` asset.
- Top Shelf extension has a strict binary + resource limit (~5MB compressed). Keep it thin.
- Enable "Extra Large" asset thinning to avoid shipping @1x/@2x variants your TV doesn't need.

(Confidence: **HIGH**.)

---

## 11. Anything else a senior tvOS engineer would use

### SwiftLint — https://github.com/realm/SwiftLint
- Stars: 19,643. Last release: 0.65.0 (2026-06-27). Active weekly-ish releases.
- Runs on macOS build machines; lints the Swift source regardless of target platform. tvOS support is not a concern (it doesn't run on-device).
- Verdict: **USE.** Adopt a starter config and tune down; do not paste every rule.

### SwiftFormat — https://github.com/nicklockwood/SwiftFormat
- Stars: 8,847. Last release: 0.61.1 (2026-04-27). Active.
- Same story as SwiftLint. Some overlap with SwiftLint's autocorrect but SwiftFormat is more aggressive/opinionated on layout.
- Verdict: **USE (pick one of the two as the "formatter of record"; use the other for lint-only).**

### swift-log — https://github.com/apple/swift-log
- Stars: 4,032. Last push: 2026-06. `Package.swift` doesn't restrict platforms → works everywhere including tvOS.
- Server-side Swift log facade. On Apple platforms, prefer `os.Logger` (built into Foundation) — swift-log is more relevant if you have shared code between the tvOS app and a Swift backend.
- Verdict: **SKIP for the app.** USE if you write the backend in Swift and want a shared logger.

### swift-collections — https://github.com/apple/swift-collections
- Stars: 4,444. Last push: 2026-07. Works on tvOS (no platform restriction).
- Provides `OrderedSet`, `OrderedDictionary`, `Deque`, `Heap`, `BitSet`, etc. Genuinely useful for a media grid app: `OrderedDictionary` keyed by post ID for the feed cache; `Deque` for a recently-viewed ring buffer; `Heap` for the AVPlayer eviction pool.
- Verdict: **USE.** Zero risk, small binary cost. (Confidence: **HIGH**.)

### The Composable Architecture — https://github.com/pointfreeco/swift-composable-architecture
- Stars: 14,786. Last release: 1.26.0 (2026-06-09). `Package.swift`: `.tvOS(.v16)`. README: "SwiftUI, UIKit, and more, and on any Apple platform (iOS, macOS, iPadOS, visionOS, **tvOS**, and watchOS)."
- Works on tvOS. Two questions:
  1. **Will your team enjoy TCA?** TCA introduces a strong shape (Reducer / Action / State / Effect) and a real learning curve. It shines when you have deeply nested state and complex effects. A Patreon viewer app has moderate state (feed, playback, focus) — enough that TCA would help, not so much that vanilla `@Observable` couldn't cope.
  2. **tvOS-specific tax:** TCA's tests and the recording/debugging story are well-worn on iOS but slightly less trodden on tvOS. Not a blocker; just budget for occasional "am I holding tvOS's focus API right in a reducer" head-scratchers.
- Verdict: **MAYBE.** Recommend it *only* if the team has TCA experience. For a first tvOS project I'd start with `@Observable` + a thin service layer, and revisit TCA if state gets tangled. (Confidence: **MEDIUM**.)

### Bonjour / mDNS on tvOS (worth mentioning)
Not asked but relevant if you take inspiration from `kochj23/PatreonTV`'s local-relay pattern. `Network.framework`'s `NWBrowser`/`NWListener` is the modern way — no third-party lib needed.

### Analytics on the backend
If you go Node, **Pino** or **Winston** for logs; **OpenTelemetry** if you want traces. Not per-request-critical for a small OAuth service, but worth mentioning that OpenTelemetry has first-class Node and Go SDKs and is the future of "observability across app + backend".

---

## Final recommended stack

### tvOS app (`Package.swift` dependencies)

```
.package(url: "https://github.com/kean/Nuke",                              from: "13.0.0"), // + NukeUI product
.package(url: "https://github.com/kishikawakatsumi/KeychainAccess",        from: "4.2.2"),
.package(url: "https://github.com/apple/swift-collections",                from: "1.1.0"),
.package(url: "https://github.com/apple/swift-openapi-generator",          from: "1.0.0"),  // build-plugin for own-backend contract
.package(url: "https://github.com/apple/swift-openapi-runtime",            from: "1.0.0"),
.package(url: "https://github.com/apple/swift-openapi-urlsession",         from: "1.0.0"),
.package(url: "https://github.com/getsentry/sentry-cocoa",                 from: "8.0.0"),
.package(url: "https://github.com/TelemetryDeck/SwiftSDK",                 from: "2.0.0"),
// Test-only:
.package(url: "https://github.com/nalexn/ViewInspector",                   from: "0.9.0"),
.package(url: "https://github.com/pointfreeco/swift-snapshot-testing",     from: "1.17.0"),
.package(url: "https://github.com/WeTransfer/Mocker",                      from: "3.0.0"),
// Optional / tactical (opt-in as needed):
.package(url: "https://github.com/SwiftUIX/SwiftUIX",                      branch: "master"),         // for UIKit escape hatches
.package(url: "https://github.com/siteline/swiftui-introspect",            from: "1.1.0"),           // ditto
```

**Frameworks used (no package needed):** SwiftUI, UIKit, AVKit / AVFoundation, Security (Keychain), Network (Bonjour if wanted later), TVUIKit (Top Shelf), TVServices, os (Logger), MetricKit, LinkPresentation.

**Explicitly NOT recommended:** Alamofire, Moya, SDWebImage, Kingfisher (defensible alternative to Nuke — pick one), any Patreon Swift SDK, Firebase, Bitmovin Player, JW Player, THEOplayer, Vox, mattpolzin/JSONAPI (unless you want max type safety), Japx (unless you fork it for tvOS), Epoxy (iOS-only), AppAuth-iOS (unless you decide to implement RFC 8628 on your backend), Composable Architecture (unless team already knows it).

**In-repo modules to hand-write (no dependency):**
1. `PatreonClient` — URLSession + Codable + a small JSON:API decoder. ~500 lines.
2. `PlayerPool` — 2–3 recycled `AVPlayer` instances for autoplay-on-dwell. ~200 lines.
3. `PairingFlow` — polls backend for the paired token, stores via KeychainAccess. ~100 lines.

### Backend (recommended stack)

**TypeScript + Hono + `patreon-js` + `ioredis` + `drizzle-orm` + Postgres, deployed on Fly.io or Cloudflare Workers.**

- HTTP: **Hono** (portable across Node / Bun / Workers, first-class TypeScript).
- Patreon: official **`patreon/patreon-js`** — actively maintained, correct authorization-code flow.
- Session/pairing store: **`ioredis`** for `{pairing_code → session_state}` with TTL.
- Persistent store: **Drizzle** + Postgres for long-lived user↔session mappings.
- Sentry backend SDK for error tracking, mirroring the tvOS side.
- Deploy: Fly.io (VMs, straightforward) or Cloudflare Workers (edge-native, cheaper at low volume — but only if you don't add a chunked-range media proxy, which is hard on Workers).

**Backend responsibilities:**
1. Own the Patreon `client_secret` and `refresh_token` — tvOS never sees them.
2. Implement the pairing flow: `POST /pair`, `GET /pair/:code`, `GET /oauth/callback`.
3. Proxy the JSON:API surface (or expose a smaller shaped-for-TV API — probably preferable).
4. Resolve Patreon media URLs (follow CDN redirects with the session cookie) and either 302 or chunked-proxy to AVPlayer. This is the piece worth studying `kochj23/PatreonTV` for.

**Second-choice backend:** **Go + chi + go-redis + sqlc on Fly.io** — pick this if the team is Go-native or if the proxy layer becomes central (Go handles streaming proxies more gracefully than Node).

### Distribution
Xcode Cloud → TestFlight for v1. Migrate to GitHub Actions + Fastlane if/when needed.

---

## Confidence summary per major recommendation

| Area | Recommendation | Confidence | Why |
|------|----------------|-----------|-----|
| Patreon Swift SDK | Roll your own | **HIGH** | No official SDK; third-party options are archived / non-tvOS / one-person / 0–4 stars |
| Image cache | Nuke + NukeUI | MEDIUM-HIGH | All three (Nuke, Kingfisher, SDWebImage) work; Nuke best fits SwiftUI-first + performance |
| Video | AVPlayerViewController + own PlayerPool | **HIGH** | Enterprise players only justified by DRM/SSAI, which you don't need |
| Networking | URLSession + async/await, no Alamofire | **HIGH** | Small API surface, modern Swift concurrency, no ergonomic gap |
| JSON:API decoder | Hand-write ~200 lines | MEDIUM-HIGH | Japx is defensible but doesn't declare tvOS in SPM; Vox dead; mattpolzin heavy |
| OAuth pairing | Hand-write ~100 lines client + backend endpoints | **HIGH** | No existing lib fits Patreon's constraint (no RFC 8628, no PKCE, no app-scheme redirects) |
| Keychain | KeychainAccess | **HIGH** | Battle-tested, tvOS explicit, stable API |
| Focus / SwiftUI | Native + SwiftUIX/introspect as tactical | MEDIUM-HIGH | No "shelves in a box" library exists; Epoxy is iOS-only |
| Backend | Node + Hono + patreon-js + ioredis + Drizzle | MEDIUM | Driven by official SDK availability; Go is a close second |
| Analytics | Sentry + TelemetryDeck + OSLog + MetricKit; **skip Firebase** | **HIGH** | Firebase Crashlytics on tvOS is explicit "beta" support |
| Testing | ViewInspector + swift-snapshot-testing + Mocker + XCTest | **HIGH** | All declare tvOS; snapshot-testing README explicitly names tvOS |
| Distribution | Xcode Cloud → TestFlight, migrate later | MEDIUM-HIGH | Fastest path; migrate to Fastlane/GHA when needed |
| TCA | Only if team knows TCA | MEDIUM | Works on tvOS but adds cognitive load; `@Observable` likely enough |
| swift-collections | Use | **HIGH** | Zero-risk, tvOS works, small footprint, useful data structures |
| Linters | SwiftLint + SwiftFormat | **HIGH** | Standard; runs on build host |

---

## Files produced by this research

Raw evidence in `/tmp/library-research/`:

- **READMEs (51 files, ~800KB):** `*_README.md` — one per library fetched.
- **Package.swift files (44 files):** `*_Package.swift` — used to verify tvOS platform declarations. Files ≤14 bytes represent 404s (repo has no Package.swift, e.g. non-Swift repos).
- **Repo metadata (49 files):** `*_repo.json` — GitHub REST API responses. About a dozen were rate-limited (contain `{"message": "API rate limit exceeded ..."}` instead of repo data); for those, README + platform declarations + widely-known repo reputation carried the analysis.
- **Release history:** `*_releases.json` — latest 5 releases with tags and dates.
- **Patreon org repo list:** `patreon_org_repos.json`, `patreon_org_repos.tsv` — confirms no official Swift SDK.
- **Patreon docs pages:** `patreon_docs_root.html`, `patreon_oauth2_docs.html`, `patreon_oauth_docs.html` — confirmed JSON:API usage and authorization-code-only OAuth model.

This report: `/tmp/library-research/FINDINGS.md`.
