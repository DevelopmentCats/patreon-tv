# PatreonTV — the couch-first Patreon client for Apple TV

A native tvOS app for watching your favorite Patreon creators on the big screen.

- **One app.** No companion. No LAN server. Downloaded from the App Store, sign in once, done.
- **Netflix-style browsing.** Focus-driven shelves, hero art that follows what you're looking at, snappy transitions.
- **Native video.** Patreon-hosted video plays directly in `AVPlayer` via signed Mux HLS — no proxy, HDR, PiP, AirPlay.
- **Free & open source** — MIT.

## Status

**Early scaffolding.** Do not attempt to ship yet. See [`PLAN.md`](./PLAN.md) for the full architecture, research, and roadmap.

## Repo layout

```
patreon-tv/
├── apps/tvos/          The Apple TV app (SwiftUI, tvOS 17+, XcodeGen)
├── services/pairing/   OPTIONAL push/notifications service — not required for v1
├── harness/            Node scripts for live-testing the Patreon API
├── docs/               Research, live-probe results, prior art analysis
│   ├── patreon-api-docs.md          Extracted Patreon official API docs
│   ├── patreon-research.md          Evidence-based research w/ live-probe §14
│   ├── library-research.md          Swift/tvOS library evaluation
│   ├── media-clients-prior-art.md   Swiftfin, VLC, Kodi, Stremio review
│   └── patreon-internal-api-openapi.yaml  Community-maintained internal API spec
├── references/         Cloned reference apps + extracted Swift patterns
│   ├── kochj23-PatreonTV/    Prior-art Patreon tvOS client (MIT)
│   ├── swiftfin_code/        Jellyfin tvOS canonical patterns
│   ├── stingray_code/        More tvOS patterns
│   └── sashimi_code/         Custom-focus-effect reference
├── live-tests/         Redacted JSON from real Patreon API probes
├── skills/             Vendored Agent Skills (SwiftUI Expert, tvOS Design, Xcode Setup)
└── .agents/skills/     Symlinks to the vendored skills (repo-wide auto-load)
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
