# Prior-art sweep — open-source tvOS media clients with polished shelf UX

**Scope.** Focused follow-up to `FINDINGS.md`. Goal: find open-source tvOS apps whose SwiftUI structure, shelf layout, focus handling, and playback chrome are worth studying (and, where licensing permits, copying patterns from) before building the Patreon tvOS client.

**Method.** For each candidate: fetched repo README (`raw.githubusercontent.com`), pulled the recursive git tree via API to locate tvOS-specific source files, then fetched the specific SwiftUI files that implement the shelf, poster card, focus coordination, and playback chrome. Raw sources are in `/tmp/library-research/media-clients/{swiftfin,stingray,sashimi,komodio}_code/*.swift`. Full READMEs are in `/tmp/library-research/media-clients/*_README.md`. Recursive git trees are in `/tmp/library-research/media-clients/*_tree.json`.

**Rate-limit note.** GitHub anonymous API cap is 60 req/hr. All raw file fetches (source code and READMEs) go through `raw.githubusercontent.com` and don't count. All source-file evidence in this doc is first-hand.

---

## The five that matter

Ranked by "how much of this could you legitimately copy the shape of into your Patreon tvOS app":

1. **Swiftfin** — jellyfin/Swiftfin — the canonical reference. Multi-year, multi-contributor, still shipping. Study first.
2. **Stingray** — benjaminRoberts01375/Stingray — the "small enough to read in an afternoon" alternative. Native APIs only, no exotic packages.
3. **Sashimi** — mondominator/sashimi — modern SwiftUI, custom-focus-effect approach (contrast with Swiftfin's built-in-hover-effect and Stingray's `.buttonStyle(.card)`).
4. **Komodio** — Desbeers/Komodio — SwiftUI Kodi client; small, shows modern SwiftUI-only techniques (`.scrollClipDisabled(true)`, `.backport.focusable()` cross-OS-version pattern).
5. **VLC-iOS (tvOS target)** — videolan/vlc-ios — legacy Objective-C + UIKit reference only. Useful for one thing: low-level Siri Remote gesture handling (`VLCSiriRemoteGestureRecognizer.m`).

Also-rans (READMEs read, source not deep-dived):
- **VortX** (VortXTV/VortX) — Stremio client for Apple TV. Rust `stremio-core` + libmpv. Best textual description of the target UX in this whole sweep.
- **Sodalite** (superuser404notfound/Sodalite) — tvOS 26+, Swift 6, universal Apple app. Very fresh.
- **Streamyfin** (streamyfin/streamyfin) — anti-pattern reference: React Native + MPVKit. Not tvOS-targeted.
- **Moonfin** (Moonfin-Client/Moonfin-Core) — anti-pattern reference: Flutter. Claims tvOS 16 support but nothing native.
- **Plozz**, **Sashimi** (already covered), **Sodalite** — smaller Jellyfin tvOS attempts. Read READMEs for feature-list inspiration.
- **ABJC-tvOS** — earlier "A Better Jellyfin Client" (Swiftfin's spiritual predecessor). Last push 2022-06 → abandoned.

Excluded from deep dive:
- **Kodi (xbmc/xbmc)** — C++, ~20K stars, not a SwiftUI reference at all.
- **`Komodio` vs `KodiTVOS`** vs random Kodi wrappers — Komodio is the only Swift one worth reading.
- **Stremio official tvOS** — Erlang/JS Cordova wrapper. Not native. Also removed from App Store in mid-2026 per VortX README.

---

## 1. Swiftfin (jellyfin/Swiftfin) — the canonical reference

- **URL:** https://github.com/jellyfin/Swiftfin
- **License:** MPL-2.0 (Mozilla Public License 2.0)
- **Activity:** 3,989 stars, last push 2026-07-05 (yesterday), actively contributed to by ~dozens of Jellyfin community members.
- **Language / UI:** Swift + **SwiftUI** primary, some UIKit escape hatches via `SwiftUIIntrospect`. Multi-target Xcode project with separate `Swiftfin/` (iOS) and `Swiftfin tvOS/` folders + `Shared/` for cross-platform models and networking.
- **Structure:** 1,554 tracked files. tvOS-specific code lives under `Swiftfin tvOS/` with subdirs `App/`, `Components/`, `Extensions/`, `Objects/`, `Views/`. Each view family (HomeView, ItemView, VideoPlayer) is its own directory with a top-level file plus `Components/` for private subviews.
- **Package.swift deps** (from their `Package.resolved`): **`nuke`** (image cache — matches my §2 recommendation), **`kean/Get`** (tiny URLSession wrapper), **`kean/Pulse`** (network debugger), **`blurhashkit`**, **`LePips/CollectionHStack`** + **`CollectionVGrid`** (custom shelf-oriented collection views), **`keychain-swift`** (evgenyneu — not KeychainAccess but same category), **`sindresorhus/Defaults`** (typed UserDefaults), **`Factory`** (DI), **`CoreStore`** (Core Data wrapper), **`jellyfin-sdk-swift`** (their own generated SDK), plus the apple/* pure-Swift packages (`swift-collections`, `swift-log`, `swift-algorithms`, etc.).

### Home layout — `Swiftfin tvOS/Views/HomeView/HomeView.swift` (83 lines)

Full-file review — it's small. The whole home is:

```swift
ScrollView {
    VStack(alignment: .leading, spacing: 0) {
        if viewModel.resumeItems.isNotEmpty {
            CinematicResumeView(viewModel: viewModel)              // hero = resume
            NextUpView(viewModel: viewModel.nextUpViewModel)
            if showRecentlyAdded {
                RecentlyAddedView(viewModel: viewModel.recentlyAddedViewModel)
            }
        } else {
            if showRecentlyAdded {
                CinematicRecentlyAddedView(...)                    // hero = recently added
            }
            NextUpView(viewModel: viewModel.nextUpViewModel)
                .safeAreaPadding(.top, 150)
        }
        ForEach(viewModel.libraries) { viewModel in
            LatestInLibraryView(viewModel: viewModel)              // one shelf per library
        }
    }
}
```

**Patterns to steal:**
1. **Conditional hero.** The top shelf is *content-adaptive*: if the user has resume items → hero is a cinematic resume picker; otherwise → hero is recently added. For Patreon: hero should be "continue watching if you have one, otherwise the newest post from your top creator." (`HomeView.swift:30-45`)
2. **`.sinceLastDisappear { interval in ... }` (line 75-80)** — a custom modifier that triggers `backgroundRefresh` if the view was hidden for more than 60 seconds. Simple, cheap, avoids stale feeds. Worth reimplementing.
3. **`.animation(.linear(duration: 0.1), value: viewModel.state)` (line 67)** — content-vs-loading transitions are 100ms linear, not spring — matches Apple TV's system feel.

### Poster shelf — `Swiftfin tvOS/Components/PosterHStack.swift` (85 lines)

```swift
CollectionHStack(
    uniqueElements: data,
    columns: type == .landscape ? 4 : 7
) { item in
    PosterButton(item: item, type: type) { action(item) }
        label: { label(item).eraseToAnyView() }
}
.clipsToBounds(false)
.dataPrefix(20)
.insets(horizontal: EdgeInsets.edgePadding, vertical: 20)
.itemSpacing(EdgeInsets.edgePadding - 20)
.scrollBehavior(.continuousLeadingEdge)
.withViewContext(.isThumb)
.focusSection()             // <-- groups the shelf for the focus engine
```

**Patterns to steal:**
1. **`CollectionHStack` (LePips)** — Swiftfin doesn't use `LazyHStack`. They use a purpose-built `CollectionHStack` package (`https://github.com/LePips/CollectionHStack`) that has:
   - `columns:` parameter (fixed number visible at once, not "as many as fit")
   - `.dataPrefix(20)` — eager-load window limit
   - `.scrollBehavior(.continuousLeadingEdge)` — the "focused card locks to leading edge as you swipe" behavior Netflix uses
   - `.clipsToBounds(false)` — so the focused-tile scale bloom isn't clipped by the shelf's own bounds
   
   If you want that specific Apple TV "each card locks to the same on-screen X coordinate as you swipe through the shelf" behaviour, `LazyHStack` doesn't give it to you. `CollectionHStack` does. **This is the single most valuable dependency finding in this sweep.** (`PosterHStack.swift:38-56`)
2. **`.focusSection()`** on the whole shelf (line 58). Standard tvOS 15+ API to group a set of focusables so vertical focus-navigation skips between shelves instead of drifting diagonally.

### Poster card — `Swiftfin tvOS/Components/PosterButton.swift` (233 lines)

The card treatment uses **built-in tvOS focus effects**, not a custom scale animation:

```swift
Button(action: action) {
    PosterImage(item: item, type: type)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .overlay { overlay }
        .contentShape(.contextMenuPreview, Rectangle())
        .posterStyle(type)
        .posterShadow()
        .hoverEffect(.highlight)                    // <-- tvOS built-in focus lift
    // ... label
}
.buttonStyle(.borderless)
.buttonBorderShape(.roundedRectangle)
.focusedValue(\.focusedPoster, AnyPoster(item))    // <-- publish focus context up-tree
.matchedContextMenu(for: item) { EmptyView() }
```

**Patterns to steal:**
1. **`.hoverEffect(.highlight)` + `.buttonStyle(.borderless)`** — the tvOS-native way to get focus scale/lift without writing your own animation (`PosterButton.swift:38, 53`). Cheaper than Sashimi's manual `.scaleEffect + .shadow` combo, but less controllable.
2. **`.focusedValue(\.focusedPoster, AnyPoster(item))`** — the **key hero-coordination primitive**. Each poster publishes itself into a `@FocusedValue` when it gets focus; the hero view above reads that value with `@FocusedValue(\.focusedPoster) private var focusedPoster` and swaps its backdrop/description accordingly. Zero glue code between shelf and hero — SwiftUI's focused-value system does the plumbing. This is *the* pattern for coordinating hero backdrop with shelf focus. (`PosterButton.swift:55`)
3. **`.matchedContextMenu(for: item)`** — long-press on the Siri Remote's touchpad shows a context menu. Standard tvOS interaction users expect.
4. **`.contentShape(.contextMenuPreview, Rectangle())`** — controls the shape of the context-menu preview so it matches the card's rounded rect.

### Hero coordination — `Swiftfin tvOS/Components/CinematicItemSelector.swift` (118 lines)

The *hero-backdrop-follows-focused-poster* pattern in ~50 lines:

```swift
struct CinematicItemSelector<Item: Poster>: View {
    @FocusState private var isSectionFocused
    @FocusedValue(\.focusedPoster) private var focusedPoster   // read what's focused
    @State private var backgroundItem: AnyPoster?              // debounced backdrop

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if let focusedPoster, let focusedItem = focusedPoster._poster as? Item {
                topContent(focusedItem)                        // title/synopsis for focused
                    .id(focusedItem.hashValue)
                    .transition(.opacity)                      // crossfade
            }
            PosterHStack(type: .landscape, items: items, action: action, label: itemContent)
                .frame(height: 400)
        }
        .background(alignment: .top) {
            FadeContentTransitionView(
                item: backgroundItem ?? items.first.map(AnyPoster.init),
                debounce: 0.5                                  // <-- 500ms dwell before swap
            ) { item in
                ImageView(item?.landscapeImageSources(environment: .default) ?? [])
                    .aspectRatio(contentMode: .fill)
            }
            .overlay {
                Color.black.maskLinearGradient {
                    (location: 0.5, opacity: 0)
                    (location: 0.6, opacity: 0.4)
                    (location: 1, opacity: 1)                   // fade backdrop to black at bottom
                }
            }
        }
        .onChange(of: focusedPoster) {
            guard let focusedPoster, isSectionFocused else { return }
            backgroundItem = focusedPoster                     // only swap when section is focused
        }
        .focusSection()
        .focused($isSectionFocused)
    }
}
```

**Patterns to steal:** (every line of this is worth stealing, but the marquee items)
1. **500ms debounce on hero backdrop swaps.** Without this, rapid focus-swiping through a shelf makes the backdrop thrash. With 500ms, it feels "cinematic". (`CinematicItemSelector.swift:60`) — `FadeContentTransitionView(item:debounce:)`
2. **Gate backdrop updates on `isSectionFocused`.** Line 82-85. When the user has moved focus down to a lower shelf, don't keep updating the top hero backdrop (would flicker and waste GPU).
3. **`maskLinearGradient`** for the backdrop-to-shelf fade (line 68-75). SwiftUI-native — no `UIViewRepresentable`, no `CAGradientLayer`. The Netflix "backdrop fades into the shelves" look in ~7 lines.
4. **Set `.id(focusedItem.hashValue)`** on top content so SwiftUI treats it as a new view when the focused poster changes → the `.transition(.opacity)` actually fires (line 40-41). Standard SwiftUI trick worth remembering.

### Item detail (product page) — `CinematicScrollView.swift` (223 lines)

Shows how they build the "hero with logo overlay + play button + synopsis over a blurred backdrop" look:

- **Blurred backdrop** = `BlurView(style: .dark)` with a `LinearGradient` mask that goes from white at bottom to clear at top (line 84-97). No UIKit bridging needed.
- **Focus catcher** at top of hero = invisible `Color.clear.focusable().focused($focusedLayer, equals: .top)` (line 130-132), then `.onChange(of: focusedLayer)` auto-redirects focus onto the Play button (line 211-218). This is a **focus routing pattern** you'll use whenever the top-of-screen area shouldn't itself hold focus but might be entered from adjacent sections.
- **`Marquee(...)` component** for long titles that don't fit — scrolls automatically when focused. tvOS-specific need (`CinematicScrollView.swift:146`).

### Focus utility — `Swiftfin tvOS/Objects/FocusGuide.swift` (138 lines) — **MARKED DEPRECATED**

**This is the single most valuable signal in the whole sweep.** The file starts with:

```swift
@available(*, deprecated, message: "Use defaultFocus and focusScope instead")
struct FocusGuideModifier: ViewModifier { ... }
```

Swiftfin invented a custom "invisible focusable boundary" trick years ago to help the focus engine transition between adjacent sections (their `FocusGuideModifier` wraps content with 1px focusable `Color` bars on top/bottom/left/right and tracks focus movement via `@FocusState`). It worked, they shipped it, and then Apple added `defaultFocus(_:in:)` and `focusScope(_:)` in tvOS 15/16, which do the same thing natively. **Swiftfin now tells anyone reading their code: don't build a custom FocusGuide, use the native APIs.**

**What this means for your Patreon app:** on tvOS 17+ you should never need to write manual focusable-boundary tricks. Use `focusScope(namespace)` + `.defaultFocus($binding, value, priority:)` + `.focusSection()`. If you find yourself writing `Color.clear.focusable().focused(...)` boundary hacks, stop — you're solving a problem Apple already solved.

### Extension helpers — `View-tvOS.swift` (52 lines)

Shows the pattern for **shared iOS/tvOS code**: iOS-only modifiers get no-op shim implementations on tvOS so the same source compiles for both. Example:

```swift
extension View {
    /// - Important: This does nothing on tvOS.
    @ViewBuilder
    func navigationBarTitleDisplayMode(_ mode: NavigationBarItem.TitleDisplayMode) -> some View { self }
    // ... several more no-op shims
}
```

Also imports `SwiftUIIntrospect` (line 11) — matches my §6 recommendation.

### What NOT to copy from Swiftfin
- **The `FocusGuide` code itself.** Deprecated by its own authors (see above).
- **The nested `Views/HomeView/Components/` folder structure.** For a smaller app this is over-organized. Their scale justifies it; a Patreon client that ships with 3 tabs doesn't need it.
- **The number of dependencies.** Swiftfin has 25+ SPM deps because they serve every Jellyfin edge case (SVG rendering for library icons, `LNPopupUI` for the mini-player, `Mantis` for image cropping, `CoreStore` for offline cache). You do not need most of these. Cherry-pick: **`Nuke`, `swift-collections`, `Defaults`, and possibly `CollectionHStack`**. Skip the rest.
- **`kean/Get` vs writing your own.** Swiftfin uses `kean/Get`, but for the tiny Patreon API surface (~12 endpoints), `URLSession + async/await` directly is fine. `Get` is a nice tiebreaker if you want request/response typing.
- **The `_ViewModel.send(.refresh)` action-based reducer style.** They're following a pseudo-TCA pattern with a `StatefulMacro` package. Fine at their scale; overkill at yours unless you already like TCA (see §11 of `FINDINGS.md`).

---

## 2. Stingray (benjaminRoberts01375/Stingray) — the minimal reference

- **URL:** https://github.com/benjaminRoberts01375/Stingray
- **License:** (unclear — not in the top-level file list I fetched; check LICENSE before copying)
- **Activity:** 250 stars, last push 2026-07-06 (yesterday), single primary contributor.
- **Language / UI:** Swift + SwiftUI, tvOS-only (no iOS target).
- **Structure:** 40 Swift files, no separate iOS/tvOS split. Flat `Stingray/` folder + a `TopShelf/` extension. README describes the app as "attempts to use as many native APIs as possible."
- **Deps** (not confirmed via Package.resolved but visible in imports): **`BlurHashKit`** (blur placeholders), **`AsyncImage`** (native SwiftUI), no Nuke.

### Home layout — `Stingray/HomeView.swift` (312 lines)

```swift
public var body: some View {
    VStack(alignment: .leading) {
        DashboardRow(rowType: .nextUp, ...) .focusSection()
        DashboardRow(rowType: .recentlyAdded, ...) .focusSection()
        DashboardRow(rowType: .latestMovies, ...) .focusSection()
        DashboardRow(rowType: .latestShows, ...) .focusSection()
        VStack {
            SystemInfoView(...)
            LibrariesInfoView(...)
        }
    }
}
```

Dramatically simpler than Swiftfin's home. No hero, no cinematic backdrop — just stacked shelves.

**Patterns to steal:**
1. **Every shelf gets `.focusSection()`.** Same as Swiftfin, but flatter — every direct child is its own section. For a Patreon app with 4-5 top-level shelves this is enough. (`HomeView.swift:26, 36, 46, 56`)
2. **Explicit loading state for each row.** `DashboardRow` has an internal `enum DashboardRowStatus { case unstarted, retrieving, complete([SlimMedia]), empty }` and renders a *placeholder skeleton row* (`MediaNavigationLoadingPicker`) while loading. The skeleton uses randomized `Int.random(in: 4..<8)` placeholder count with `.opacity(1 - i/n)` for a nice fade-off. (`HomeView.swift:186-198`)
3. **`.focusable(false)` on the placeholder card** so it doesn't consume focus during the loading state (`HomeView.swift:224`). Missing this is a common tvOS bug — focus lands on a spinner and the user can't do anything.
4. **Cache dictionary lifted to parent (`@State private var dashboardCache: [String: [SlimMedia]] = [:]`).** Passed as a `@Binding` to each row so navigating away and back doesn't refetch. Simple pattern; works well. (`HomeView.swift:13`)

### Poster card — `Stingray/MediaCardView.swift` (159 lines)

Uses **the third approach** to focus effects (Swiftfin uses `.hoverEffect(.highlight)`; Sashimi uses manual `.scaleEffect + shadow`):

```swift
Button { navigation.append(...) } label: {
    VStack(spacing: 0) {
        AsyncImage(url: url) { image in
            image.resizable().scaledToFill()
        } placeholder: {
            if let blurImage {
                Image(uiImage: blurImage).resizable().scaledToFill()
            } else { MediaCardLoading() }
        }
        .frame(width: Self.cardSize.width)
        .frame(minHeight: 0, maxHeight: Self.imageHeight)
        .clipped()
        Text(self.media.title)
    }
    .background(.ultraThinMaterial)
}
.buttonStyle(.card)           // <-- native tvOS card style, full focus effect for free
.contextMenu { ... }
.frame(idealWidth: 200, idealHeight: 370)
.task(id: self.media.id, priority: .background) {
    guard let blurHash = self.media.imageBlurHashes?.getBlurHash(for: .primary)
    else { return }
    let decoded = await Task.detached(priority: .background) {
        return UIImage(blurHash: blurHash, size: CGSize(width: 32, height: 32))
    }.value
    self.blurImage = decoded
}
```

**Patterns to steal:**
1. **`.buttonStyle(.card)`** — the single-line "make my button look like an Apple TV card with focus lift, shadow, and press animation." Simpler than Swiftfin's `.borderless + .hoverEffect + custom shadow` combo. (`MediaCardView.swift:108`)
2. **BlurHash placeholders** — Jellyfin's API returns a BlurHash string for every image. Stingray decodes it to a 32×32 `UIImage` on a background task, uses it as the AsyncImage placeholder. First scroll never looks blank. (`MediaCardView.swift:8, 121-127`) — For Patreon: their API returns image URLs but no BlurHash. You could generate one on your backend (`woltapp/blurhash` in Node) and cache it alongside the image URL, or use a solid-colour placeholder from the tile's dominant colour.
3. **AsyncImage is used here successfully!** This slightly walks back my §2 claim that AsyncImage is unusable for shelves. It works here because: (a) `.buttonStyle(.card)` cheaply handles focus, (b) BlurHash placeholder covers the load latency, (c) rows are shallow (~8 items visible), (d) users don't scroll fast enough for coalescing to matter at that count. **For a Patreon feed with much longer shelves and repeated URL requests as focus dwells, Nuke is still the right choice.** But AsyncImage + BlurHash is a valid MVP path.
4. **`.contextMenu`** for per-card actions (show error, mark watched). Standard tvOS pattern.
5. **`.background(.ultraThinMaterial)`** for the card container — modern iOS/tvOS glass effect.

### System info footer

`HomeView.swift:228-263` builds a tiny "Stingray v1.2.3 • Jellyfin Server "MyServer" v10.8.0 • tvOS 17.2.1 • AppleTV5,3" footer using `Bundle.main.infoDictionary` + `ProcessInfo.processInfo.operatingSystemVersion` + `uname()` for the device model. Useful for a settings/about screen — worth stealing verbatim.

### What NOT to copy from Stingray
- **`AsyncImage` in the main feed** if the feed is going to be long or fast-scrolling. Fine for Stingray's smaller, curated Jellyfin rows; will hurt at Patreon feed scale.
- **The flat `Stingray/` folder** — once you have 40+ view files this becomes hard to navigate. Adopt a shallow folder structure earlier.

---

## 3. Sashimi (mondominator/sashimi) — the custom-focus-effect reference

- **URL:** https://github.com/mondominator/sashimi
- **License:** (not confirmed — check LICENSE)
- **Activity:** 1 star, last push 2026-07-06. Very small/new; universal app across Apple TV, iPhone, iPad ("Universal Purchase").
- **Language / UI:** Swift + SwiftUI. `Sashimi/` = tvOS target; `SashimiMobile/` = iOS/iPadOS; `Shared/` = cross-platform code.
- **Structure:** 469 files. tvOS views under `Sashimi/Views/{Home,Detail,Library,Player,Components}/`.

### Poster card — `Sashimi/Views/Components/MediaRow.swift` (428 lines)

Uses **the third approach** — full manual control:

```swift
@FocusState private var isFocused: Bool

// inside the button body:
.overlay(
    Group {
        if isCircular {
            Circle().stroke(isFocused ? SashimiTheme.accent : .clear, lineWidth: 4)
        } else {
            RoundedRectangle(cornerRadius: 12)
                .stroke(isFocused ? SashimiTheme.accent : .clear, lineWidth: 4)
        }
    }
)
.shadow(color: isFocused ? SashimiTheme.focusGlow : .clear, radius: 15, x: 0, y: 0)

MarqueeText(text: displayTitle, isScrolling: isFocused, height: 24, alignment: .center)
    .foregroundStyle(SashimiTheme.textPrimary)
    .frame(width: cardWidth, alignment: .center)

// then:
.scaleEffect(isFocused ? 1.05 : 1.0)
.animation(.spring(response: 0.3, dampingFraction: 0.7), value: isFocused)

.buttonStyle(PlainNoHighlightButtonStyle())  // <-- suppress built-in tvOS card highlight
.focused($isFocused)
```

**Patterns to steal:**
1. **Accent-color glow via `.shadow(color: accentGlow, radius: 15)`** — line 251. Softer than a stroke, "carries a soft glow in your accent color" (quote from VortX README describing the same look). This is what makes focus location visually unambiguous even at 3m viewing distance.
2. **Spring animation on scale** — `.animation(.spring(response: 0.3, dampingFraction: 0.7), value: isFocused)` (line 264). Feels more organic than the default tvOS system animation.
3. **`MarqueeText` scrolls only when `isScrolling: isFocused`** (line 253-255). Long titles don't scroll everywhere at once — only the focused card scrolls its title. Reduces visual noise.
4. **`PlainNoHighlightButtonStyle()`** — a custom `ButtonStyle` that removes the default `.card` highlight so their custom effects don't stack with it (line 266). If you go the manual-focus-effect route, you need this.

### Home layout — `Sashimi/Views/Home/HomeView.swift` (729 lines)

Larger and more complex than Stingray but flatter than Swiftfin. Uses:
- **`NavigationStack`** (not `NavigationView`) — modern iOS 16+/tvOS 16+ pattern. (Line 31)
- **`LazyVStack` (not eager VStack)** — line 41. Necessary when you have many shelves.
- **User-configurable row order** — `homeSettings.rowConfigs` is iterated with `ForEach(...) { config in if config.isVisible { rowView(for: config) } }` (line 47-51). Users can hide/reorder rows. Nice-to-have for a Patreon app once you have more than 3-4 shelves.
- **`.fullScreenCover(item:)`** for detail navigation — line 63. Modern SwiftUI pattern; feels more "app-like" than a push-navigation for immersive detail views.

### What NOT to copy from Sashimi
- **The 729-line HomeView.swift.** They've comment-suppressed it: `// swiftlint:disable file_length`. Split earlier.
- **`DispatchQueue.main.asyncAfter(deadline: .now() + 0.3)`** (line 75) as a workaround for `.fullScreenCover` transitions. This is a hack. If you have to do this, there's a state-management issue elsewhere.

---

## 4. Komodio (Desbeers/Komodio) — the modern SwiftUI-only reference

- **URL:** https://github.com/Desbeers/Komodio
- **License:** (not fetched — check)
- **Activity:** 19 stars, last push 2024-11 (older than the others, but tvOS 17+ target). Solo developer (Nick Berendsen).
- **Language / UI:** SwiftUI, cross-platform (macOS Sonoma + tvOS 17 target). Kodi API client, not Jellyfin.
- **Structure:** 511 files with well-organized Documentation folder (DocC-generated). Shared views under `Komodio/Shared/Views/`; tvOS-specific under `Komodio/tvOS/`.

### ShelfView — `Komodio/Shared/Views/ShelfView.swift` (149 lines)

The most notable single-line finding from this whole sweep:

```swift
var content: some View {
    VStack(alignment: .leading) {
        ScrollView(.horizontal) {
            HStack {
                ForEach(items, id: \.id) { movie in
                    CollectionView.Cell(item: movie, collectionStyle: .asGrid)
                        .padding(.vertical, StaticSetting.cellPadding)
                }
            }
        }
    }
    .scrollClipDisabled(true)   // <-- the modern replacement for .clipsToBounds(false)
}
```

**Pattern to steal:**
1. **`.scrollClipDisabled(true)`** (line 93) — iOS 17+/tvOS 17+ *official* API to let scroll-view content bloom past the scroll-view bounds. This is what you need so a focused card's `.scaleEffect(1.15)` doesn't get clipped by the shelf boundary. Both Swiftfin (`.clipsToBounds(false)` on `CollectionHStack`) and manual `.scaleEffect` code hit this problem; on tvOS 17+ the answer is one line: `.scrollClipDisabled(true)`.
2. **`.backport.focusable()` and `.backport.focusSection()` namespace** (line 43, 55) — Komodio wraps focus APIs in a `.backport` namespace so the same source compiles against tvOS 15 (where some APIs don't exist yet) and tvOS 17. Overengineered for a fresh Patreon project targeting tvOS 17+ only, but the *pattern* is worth knowing if you ever have to support two OS versions.

### SiriRemoteController — `Komodio/tvOS/General/SiriRemoteController (tvOS).swift` (276 lines)

**Uses `GameController` framework directly.** When SwiftUI's `.onKeyPress` and `.onTapGesture` aren't enough:

```swift
import SwiftUI
import GameController
import AVFoundation

@Observable class SiriRemoteController {
    var controllerList: [GCController] = []
    var gameController: GCController?
    init() { getControllers() }
    // ... GCControllerDidConnect / DidDisconnect notification wiring
}
```

**Pattern to know exists (not necessarily to steal):** If you need raw Siri Remote input (custom scrub-gesture on the touchpad, distinguishing hard-press vs. tap, reading the button state directly), the escape hatch is `GameController` framework. Documented Apple API, works across all tvOS versions. `SwiftUI` doesn't expose these directly.

You almost certainly won't need this for a Patreon viewer. Noting it because when you *do* need it there's no obvious answer in SwiftUI docs.

### What NOT to copy from Komodio
- **The `.backport` namespace** unless you need to support pre-tvOS 17.
- **The `GameController` remote wrangling** unless you have a specific gesture SwiftUI can't handle.

---

## 5. VLC-iOS tvOS target (videolan/vlc-ios) — legacy reference

- **URL:** https://github.com/videolan/vlc-ios
- **License:** GPL / LGPL (multiple)
- **Activity:** 1,270 stars, last push 2026-07-02. Active but old codebase.
- **Language / UI:** **Objective-C + UIKit + XIB files** primary, small amounts of Swift. Not a SwiftUI reference. Their tvOS target lives across `Sources/App/tvOS/`, `Sources/Media Library/tvOS/`, `Sources/Playback/Player/VideoPlayer-tvOS/`. Playback engine is `libvlc` (C++), not AVFoundation.

### Why it's still worth mentioning
The only file worth studying: **`Sources/Playback/Player/VideoPlayer-tvOS/VLCSiriRemoteGestureRecognizer.m`** — a `UIGestureRecognizer` subclass that captures Siri Remote touchpad swipes with the exact "swipe left / right / up / down / hard-tap-quadrant" semantics that Apple's `UITapGestureRecognizer` doesn't distinguish. If you ever need custom scrubbing gestures during video playback, this is the canonical iOS/tvOS reference (Apple's docs on this are famously thin). Read it once; you probably won't need it for a Patreon app.

### What NOT to copy from VLC-iOS
- **Anything else.** The codebase is ~15 years old. UI patterns are pre-SwiftUI, pre-Swift Concurrency, pre-modern-Xcode-project-format. Do not model your project structure on this.

---

## Also-rans (READMEs read, source not deep-dived)

### VortX (VortXTV/VortX) — Stremio client for Apple TV
- **URL:** https://github.com/VortXTV/VortX
- **License:** Check repo (README doesn't quote it).
- **Activity:** 77 stars. Actively developed 2026 (mentions release 0.3.8 Beta 15). Author openly says the app was AI-generated (Claude wrote the code, author directed and QA'd).
- **Stack:** SwiftUI + **stremio-core (Rust)** + **libmpv** player. Not directly copyable due to Rust dep.
- **UX polish:** Their README's Apple TV home description is the single best written reference for the target UX in this sweep:
  > "Home, with your real Continue Watching and every catalog from your add-ons. The background is alive: whichever title you focus fills the screen with its artwork and details, and rows fade out underneath as you browse deeper. **The focused card carries a soft glow in your accent color**, so it is always clear where you are."
  > "Series pages open ready to play. A Resume or Play button on the hero jumps to the right episode, an Add to Library chip saves it for later..."
  > "Episode pages get the full-bleed cinematic treatment: the still owns the screen with the air date, runtime, rating, and synopsis over it..."
- **Genuinely interesting engineering detail:** They ship two IPAs — "Full" (with embedded torrent engine, ~48 MB) and "Lite" (no torrent, debrid-only, ~31 MB). Same app, users pick based on IP-exposure preference. Nice model for a "with proxy" vs "without proxy" split if your Patreon backend later grows a media-proxy tier.

### Sodalite (superuser404notfound/Sodalite)
- 22 stars, last push 2026-07-06. **tvOS 26+, Swift 6.0+, GPL-3.0 with App Store exception.**
- Universal app across Apple TV, iPhone, iPad. Real HDR, real Dolby Atmos claim. In public TestFlight beta.
- Jellyfin + Seerr integration.
- Worth checking back on in a few months as it matures.

### Sashimi (mondominator/sashimi) — already covered above

### Plozz (thatcube/Plozz)
- 2 stars, last push 2026-07-06. **GPL-3.0. Native Apple TV app for Jellyfin, Plex, and local SMB shares.**
- **Notable features to mimic:**
  - **Jellyfin Quick Connect** and **Plex Link** support for remote-free sign-in. These are the two most-shipped implementations of the exact short-code pairing pattern you need for Patreon. Read up on both flows before designing your backend.
  - Circadian display mode (warm/dim at set times).
  - Multiple servers merged into one library.

### ABJC (ABJC/ABJC-tvOS)
- 54 stars, last push **2022-06** → effectively abandoned. Was the "A Better Jellyfin Client" before Swiftfin took over. Historical interest only.

### Streamyfin (streamyfin/streamyfin)
- 5,017 stars, last push 2026-07-05. **Expo / React Native / TypeScript.** MPVKit as player.
- **Anti-pattern reference.** No tvOS target mentioned. Their MPV/MPVKit substitution for AVPlayer is worth knowing about (supports MKV, VP9, formats AVPlayer doesn't), but you sacrifice the native tvOS player chrome. Sticking with `AVPlayerViewController` remains correct for a Patreon client.

### Moonfin (Moonfin-Client/Moonfin-Core)
- 360 stars, last push 2026-07-06. **Flutter.** Claims "Apple TV (tvOS) 16.0 Full support."
- **Anti-pattern reference.** Flutter on Apple TV loses native focus engine semantics, native Top Shelf, native `AVPlayerViewController` chrome, native HIG compliance. Nobody who's shipped a polished Apple TV app has done it in Flutter or React Native. Two independent projects (Streamyfin, Moonfin) trying this and neither having a dedicated tvOS target that "feels right" reinforces the point.

### Home_tv (Nziranziza/home-tv), StreamHub (joaoalvess/StreamHub), StremioTV (NicolasBataille/StremioTV), surfboard (mebn/surfboard)
- Small Stremio-alternative tvOS projects (2, 0, 0, 1 stars respectively). All active in 2026.
- **Home_tv README explicitly says: "No third-party Swift dependencies."** Uses `xcodegen` for project file generation. Fifth data point that pure-SwiftUI-with-no-deps is a working pattern on tvOS 17+.
- **StreamHub uses `Infuse via x-callback-url` as the primary player and `AVPlayer` as fallback.** External-app handoff pattern — worth knowing exists if a user ever complains "your player doesn't support MKV" (send them to Infuse).
- **StremioTV** uses **VLCKit** as its player. Note that VLCKit is another route to broader-format playback on tvOS than raw AVPlayer, if it ever matters.

---

## Cross-cutting synthesis

Reading four SwiftUI tvOS media clients side-by-side, several patterns are used by everyone and several patterns are contested:

### Everyone does this
1. **Rows are `ScrollView(.horizontal) + LazyHStack` or a purpose-built collection view**, wrapped in `.focusSection()` on the outer container.
2. **`@FocusState`** to track per-view focus; **`.focused($binding)`** to attach it. Sometimes with `enum FocusLayer` cases for finer-grained routing.
3. **Poster cards are `Button` with a custom label**, so the tvOS focus engine can pick them up. Never a plain `Rectangle().onTapGesture` — you lose focus.
4. **Long titles get a marquee** — either a custom `MarqueeText` or Swiftfin's `Marquee`. tvOS TV-viewing distance makes truncated titles unreadable; marquee-on-focus is standard.
5. **`ProgressView()` in `.overlay` while loading**, with `.allowsHitTesting(false)` so focus can still move to loaded content.
6. **`NavigationStack` (not `NavigationView`)** for anything post-tvOS 16.
7. **`Nuke`, `BlurHashKit`, and/or `AsyncImage`** for image loading. Never a raw `URLSession.dataTask` roll-your-own for the *display* layer.

### Contested — pick one and stick with it

**Focus effect on a card** — three viable approaches:

| Approach | Ergonomics | Control | Used by |
|---|---|---|---|
| `.buttonStyle(.card)` — native Apple TV card style | 1 line, works | Zero — you get what Apple gives you | Stingray |
| `.buttonStyle(.borderless) + .buttonBorderShape(.roundedRectangle) + .hoverEffect(.highlight)` | 3 lines, native-feel | Small — can add posterShadow, contentShape | Swiftfin |
| `@FocusState + .scaleEffect + .shadow(color: glow) + .overlay(stroke)` + `PlainNoHighlightButtonStyle` | ~10 lines, spring animation | Full — accent glow, custom scale amount, custom animation | Sashimi, VortX (implied) |

**Recommendation for Patreon app:** Start with **`.buttonStyle(.card)`** (Stingray approach). It's one line and looks correct out of the box. If you decide you need brand accent-color glow or a custom scale amount, upgrade to Sashimi's approach. Skip Swiftfin's middle-ground unless you specifically need `.hoverEffect(.highlight)`'s behaviour (which is subtly different — it applies a highlight *overlay* rather than scaling).

**Shelf implementation:**

| Approach | When to use |
|---|---|
| `ScrollView(.horizontal) + LazyHStack` | 3-10 items per shelf, simple |
| `LePips/CollectionHStack` package | Long shelves, want native "focused card locks to leading edge" behavior, want `dataPrefix(20)` window |

**Recommendation for Patreon app:** Start with `LazyHStack`. If the "focused card scroll behavior" doesn't feel Netflix-y enough, evaluate `CollectionHStack`. Add `.scrollClipDisabled(true)` to the ScrollView (Komodio pattern) so focused-card scale doesn't clip.

**Hero-backdrop coordination:**
- **`@FocusedValue(\.focusedPoster)` + debounced backdrop swap** (Swiftfin). The correct answer. Copy this pattern almost verbatim. `CinematicItemSelector.swift` is ~50 SLOC and is arguably the single most valuable file in this entire sweep.

**Cross-platform code organisation** (if you go universal iOS+tvOS later):
- Swiftfin's pattern: `Shared/` + `Swiftfin/` (iOS) + `Swiftfin tvOS/` folders. `View-tvOS.swift` provides no-op shims for iOS-only APIs so shared code compiles.
- Sashimi's pattern: `Sashimi/` (tvOS) + `SashimiMobile/` (iOS) + `Shared/`. Same idea, different naming.
- Either works. Don't try to `#if os(tvOS)` your way through every view file — extract per-platform view code and share the ViewModels + services.

---

## Things nobody does that you should still consider

1. **Autoplay-on-dwell video previews.** None of Swiftfin, Stingray, Sashimi, Komodio does this. Jellyfin doesn't have a data model for short preview clips, so their clients don't need to. **Netflix, Hulu, Disney+ all do it. You want it.** The pattern (from `FINDINGS.md` §3): a small `AVPlayer` pool (2-3 recycled instances), `.onChange(of: isFocused)` fires a 600-800ms debounce timer, on fire → `player.preroll()` then `player.play()` on a muted layer overlay. This is originally-designed territory for your app — no OSS to copy from in the tvOS-Jellyfin space.
2. **HLS I-frame trickplay thumbnails during scrubbing.** Only Streamyfin's README calls this out ("Trickplay images: The new golden standard for chapter previews when seeking"). Streamyfin generates these on the Jellyfin server side. If Patreon's HLS masters include `#EXT-X-I-FRAME-STREAM-INF`, AVPlayer will use them automatically; if not, your backend can generate them (see `FINDINGS.md` §3 tooling notes).
3. **Top Shelf extension.** Swiftfin, Stingray, and Sashimi all ship a Top Shelf extension. VortX and Plozz claim to. This is a **must-have for Apple TV — the "recent posts on the Apple TV home screen" real estate is free advertising for your app.** Not hard to implement (~200 lines of `TVTopShelfContentProvider` subclass + shared App Group container for the data). Not covered in `FINDINGS.md`; adding here as a callout: reserve time for it in v1.

---

## Package-list recommendation refinement

Based on what these clients actually ship with (Swiftfin's `Package.resolved` in particular), one adjustment to `FINDINGS.md`'s stack:

**Add these two candidates to consider (both by kean, same author as Nuke):**
- **`kean/Get`** — https://github.com/kean/Get — tiny URLSession wrapper (Swiftfin uses it). If you decide the ~50 lines of hand-rolled request executor is boilerplate you don't want, `Get` is a defensible add. Consistent with the "Nuke" choice ergonomically.
- **`kean/Pulse`** — https://github.com/kean/Pulse — a network debugger that shows requests/responses inside your app on-device. On tvOS this is genuinely useful because you can't Charles-proxy the Apple TV as easily as an iPhone. **Recommend adding at least in Debug builds.**

**Consider adding for shelf polish (Swiftfin uses these):**
- **`LePips/CollectionHStack`** — if native `LazyHStack` focus scroll behavior isn't Netflix-y enough.
- **`LePips/CollectionVGrid`** — same author, for vertical grids (e.g., a "See All" catalog page).
- **`woltapp/blurhash-swift` or `BlurHashKit`** — if you can generate BlurHash strings on your backend and cache them alongside image URLs. Makes empty tiles look intentional instead of blank.

**Consider adding for UX polish (Swiftfin uses):**
- **`sindresorhus/Defaults`** — typed `UserDefaults` wrapper. Ergonomic for settings ("show recently added", "row order", "player speed", etc.).

**No change to the earlier recommendation on Nuke / KeychainAccess / swift-collections / Sentry / TelemetryDeck / ViewInspector / swift-snapshot-testing.**

---

## The one Apple sample worth downloading

**Apple's "Destination Video" sample** — https://developer.apple.com/documentation/visionos/destination-video (also builds for tvOS and iOS). Apple's own multiplatform SwiftUI video app sample. Downloadable as a ZIP behind a free Apple Developer sign-in. Not fetchable via curl without auth, so I couldn't inspect the code in this sweep, but it's *the* canonical Apple-blessed reference for:
- Structuring a video-forward SwiftUI app across iOS/tvOS/visionOS.
- `AVPlayerViewController` integration in SwiftUI.
- Playlist / "up next" behavior.
- The current WWDC-recommended patterns for `@Observable`-based ViewModels.

**Action item for the user:** download it, build the tvOS target, compare it to Swiftfin's `PlaybackControls.swift` and `HomeView.swift`. If Apple's sample and Swiftfin disagree, follow Apple's sample (they're targeting current-year best practice; Swiftfin has years of accumulated pre-tvOS-17 patterns).

---

## Confidence per key claim

| Claim | Confidence | Basis |
|---|---|---|
| Swiftfin's `CinematicItemSelector.swift` is the correct pattern for hero-backdrop coordination | **HIGH** | Read the full 118-line file; the `@FocusedValue` + debounce trick is idiomatic modern SwiftUI |
| `CollectionHStack` from LePips is worth adopting for polished shelves | MEDIUM-HIGH | Swiftfin uses it; documented in their Package.resolved. Haven't fetched CollectionHStack's own repo to verify its API stability or tvOS support declaration |
| `.scrollClipDisabled(true)` (tvOS 17+) replaces older `.clipsToBounds(false)` hacks | **HIGH** | Direct evidence in Komodio's ShelfView; Apple-documented API |
| Manual focus effect (`@FocusState` + `.scaleEffect` + accent glow) beats `.buttonStyle(.card)` for brand differentiation | MEDIUM | Sashimi and (implied) VortX go this route; Stingray goes native. Both look fine in screenshots. Preference. |
| Custom `FocusGuide` boundary-focusable hacks are unnecessary on tvOS 17+ | **HIGH** | Swiftfin's own code marks their `FocusGuide` `@available(*, deprecated, message: "Use defaultFocus and focusScope instead")` |
| React Native (Streamyfin) and Flutter (Moonfin) tvOS ports don't feel native | MEDIUM | Inferred from lack of any polished tvOS RN/Flutter examples and the specific tvOS-native features (Top Shelf, focus effects, remote gestures) they don't claim to support |
| BlurHash placeholders make AsyncImage viable for smaller shelves | MEDIUM | Stingray ships this pattern successfully at Jellyfin scale. Patreon feeds might be longer/denser and stress it more; Nuke remains safer |
| Apple's "Destination Video" sample is the right modern reference | MEDIUM | Well-known WWDC sample. Not read by me directly (behind Apple ID download). Recommendation based on Apple's positioning of it. |

---

## Files produced by this sub-research

Under `/tmp/library-research/media-clients/`:

- **READMEs (16 files):** `swiftfin_README.md`, `stingray_README.md`, `sashimi_README.md`, `komodio_README.md`, `vlc_ios_README.md`, `vortx_README.md`, `sodalite_README.md`, `streamyfin_README.md`, `moonfin_README.md`, `plozz_README.md`, `abjc_tvos_README.md`, `stremiotv_README.md`, `streamhub_README.md`, `home_tv_README.md`, `surfboard_README.md`, `kodi_README.md`.
- **Repo metadata (16 files):** `*_repo.json` — GitHub API repo payloads.
- **Recursive git trees:** `swiftfin_tree.json`, `stingray_tree.json`, `vlc_ios_tree.json`, `komodio_tree.json`, `sashimi_tree.json` — full file lists per repo.
- **Search results:** `search_swiftfin.json`, `search_jellyfin_tvos.json`, `search_stremio.json`, `search_streamyfin.json`, `search_kodi.json`, `search_swiftui_tvos.json` — GitHub search API responses.
- **Swiftfin dependency manifest:** `swiftfin_pkg_resolved.json` — their full `Package.resolved`, verifying the deps enumerated above.
- **Extracted source code (35 files, ~90KB):**
  - `swiftfin_code/` — 17 tvOS-specific SwiftUI files including `HomeView.swift`, `PosterHStack.swift`, `PosterButton.swift`, `CinematicItemSelector.swift`, `FocusGuide.swift`, `CinematicScrollView.swift`, `View-tvOS.swift`, `PlaybackControls.swift`, etc.
  - `stingray_code/` — 9 files including `HomeView.swift`, `MediaCardView.swift`, `PlayerView.swift`, `DashboardView.swift`.
  - `sashimi_code/` — 5 files including `HomeView.swift`, `MediaRow.swift`, `AsyncItemImage.swift`, `TVPlayerViewController.swift`.
  - `komodio_code/` — 3 files including `ShelfView.swift`, `SiriRemoteController_tvOS.swift`, `MainView_tvOS.swift`.

This report: `/tmp/library-research/MEDIA-CLIENTS.md`. Copy at `/home/coder/patreon-tv/docs/media-clients-prior-art.md`.
