# Agent Guide for PatreonTV

If you are an AI coding agent (Claude Code, Cursor, this Coder chat, etc.) working in this repo, read this first.

## Skills — installed at `.agents/skills/`

> Workspace-only — `skills/` and `.agents/` are gitignored, like `.internal/`.
> Available on the maintainer's workspace; skip this section if the folders
> aren't present on your clone.

Load and consult these before writing code in their domain:

| Skill | Use when |
|---|---|
| `swiftui-expert-skill` | Writing or reviewing any SwiftUI code. Focus, animation, list, state, performance, latest APIs. See `skills/references/*.md` — 18 topic references. **Always check `references/latest-apis.md` first** to avoid deprecated APIs. |
| `tvos-design-guidelines` | Any tvOS design decision. 47 rules across focus, remote, 10-foot UI, top shelf, media, tab bar, accessibility. Follow the CRITICAL rules unless there's a specific reason not to. |
| `xcode-project-setup` | Modifying the Xcode project (adding SPM packages, framework links). **No Ruby, no `xcodeproj` gem.** Use the provided Swift script or XcodeGen. |

## Reference implementations — under `.internal/references/`

> These are workspace-only — vendored via `.internal/` and NOT in the public repo.
> Available on the maintainer's workspace when working with an AI agent.

- **`.internal/references/kochj23-PatreonTV/`** — a working open-source tvOS Patreon client (MIT). Architecture is Mac-companion; we're single-app. **Do NOT copy the architecture**, but the API client, model shapes, and post-type parsing are directly reusable. Read `Shared/Services/PatreonAPI.swift` and `Shared/Models/PatreonModels.swift`.
- **`.internal/references/swiftfin_code/`** — Jellyfin's tvOS client (MPL-2.0). **This is the canonical UI reference.** Key files:
  - `CinematicItemSelector.swift` — hero-follows-focus pattern using `@FocusedValue(\.focusedPoster)` with a debounced background swap
  - `PosterHStack.swift` — the shelf pattern
  - `FocusGuide.swift` — **marked deprecated by Swiftfin itself.** Use SwiftUI-native `defaultFocus` / `focusScope`.
- **`.internal/references/stingray_code/`** — another tvOS media client; uses `.buttonStyle(.card)` for poster focus.
- **`.internal/references/sashimi_code/`** — custom focus effect reference.

## Research — under `.internal/research/`

> Also workspace-only, gitignored.

- **`patreon-research.md`** (1,657 lines) — **read §14 before touching the API layer.** Live-probe findings including the Mux HLS discovery and the `current_user_can_view` restriction.
- **`patreon-api-docs.md`** — extracted Patreon official docs (public v2 API only)
- **`patreon-internal-api-openapi.yaml`** — community-maintained spec for `https://www.patreon.com/api/*` (internal API). This is what we actually hit at runtime.
- **`library-research.md`** — Swift/tvOS library evaluation.
- **`media-clients-prior-art.md`** — Swiftfin/VLC/Stremio patterns compared.

## Live-probe data — under `.internal/live-tests/`

Real Patreon API responses (redacted) from a paying-patron account. Use these as fixtures for tests. `17-internal-full.json` contains a real Mux HLS URL structure for a video post.

## Rules of engagement

1. **Read before you write.** If you're editing a screen, load `tvos-design-guidelines` and `swiftui-expert-skill/references/focus-patterns.md` first.
2. **No Ruby anywhere.** `xcode-project-setup` skill's Anti-Ruby Mandate applies to the whole repo.
3. **No Firebase Crashlytics** — its tvOS support is "official beta". Use Sentry or OSLog+MetricKit.
4. **No `AsyncImage` in shelves.** Recycles cause flicker. Use `Nuke`.
5. **Never invent auth mechanisms.** The auth flow is device pairing: the TV requests a code from the pairing portal (`site/functions/api/pairing/*`), the user signs in on their phone/computer at `patreontv.com/link/<code>`, the portal captures the `session_id` cookie, and the TV claims it and stores it in the Keychain. See `apps/tvos/PatreonTV/Sources/Auth/`.
6. **Video URLs are ephemeral** — Patreon returns Mux HLS URLs with ~24h token expiry. Never persist them; re-fetch on play.
7. **Don't commit credentials.** `harness/.env` is gitignored. Add anything sensitive to `.gitignore` before staging.
8. **Match Swiftfin's file naming conventions** where they exist — we borrow enough patterns from them that consistency helps.

## Common tasks

**"Add a new screen"** — read `swiftui-expert-skill/references/view-structure.md`, `focus-patterns.md`, and the tvOS `TAB-*` and `FOCUS-*` rules. Model after a Swiftfin view of similar shape.

**"Add an API endpoint call"** — extend `apps/tvos/PatreonTV/Sources/API/PatreonClient.swift`. Reference `.internal/research/patreon-internal-api-openapi.yaml` for the endpoint schema. Verify with a probe against `.internal/live-tests/` fixtures.

**"Style a card"** — start with `.buttonStyle(.card)`. If we need brand accent, look at `sashimi_code/`.

**"Play a video"** — `AVPlayerViewController` with `AVURLAsset(url: muxURL)`. The URL is in `Media.display.url` from the post response. No proxying needed.
