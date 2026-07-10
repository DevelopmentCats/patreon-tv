# PatreonTV — the couch-first Patreon client for Apple TV

A native tvOS app for watching your favorite Patreon creators on the big screen.

- **One app.** No companion. No LAN server. Downloaded from the App Store, sign in once, done.
- **Netflix-style browsing.** Focus-driven shelves, hero art that follows what you're looking at, snappy transitions.
- **Native video.** Patreon-hosted video plays directly in `AVPlayer` via signed Mux HLS — no proxy, HDR, PiP, AirPlay.
- **Free & open source** — MIT.

## Status

**Early scaffolding.** Do not attempt to ship yet.

## Repo layout

```
patreon-tv/
├── apps/tvos/          The Apple TV app (SwiftUI, tvOS 17+, XcodeGen)
├── site/               Marketing + legal + pairing portal + deep-link fallback
│                       (Astro → Cloudflare Pages; pairing API lives in
│                       site/functions/ as Pages Functions backed by KV)
├── harness/            Node scripts for live-testing the Patreon API
└── docs/               User-facing docs (WIP)
```

## Getting started (on a Mac)

Prerequisites:
- macOS 14+ (Sonoma)
- Xcode 16+
- [XcodeGen](https://github.com/yonaskolb/XcodeGen): `brew install xcodegen`
- Apple Developer Program membership (paid)

Steps:

```bash
git clone <this-repo>
cd patreon-tv/apps/tvos
xcodegen generate
open PatreonTV.xcodeproj
```

Choose your Apple TV or the tvOS Simulator as the run destination and build.

## Contributing

See [`AGENTS.md`](./AGENTS.md) if you're an AI coding agent working in this repo — it points you at the right skills and reference patterns for each task.

## License

MIT — see [`LICENSE`](./LICENSE).

This project is not affiliated with, endorsed by, or sponsored by Patreon.
