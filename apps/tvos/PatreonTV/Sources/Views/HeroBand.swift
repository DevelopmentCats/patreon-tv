//
//  HeroBand.swift
//  PatreonTV
//
//  The featured carousel at the top of Home. Rotates through a handful of
//  recent posts as full-width billboard slides. Each slide is a focusable link
//  into the post; because the carousel is always present and spans the full
//  width directly above the shelves, it doubles as the reliable focus
//  stepping-stone back up to the tab bar (up from any shelf lands here, up
//  again reveals the tab bar).
//

import NukeUI
import SwiftUI

struct FeaturedHero: View {

    /// Curated slides, newest-first. Reuses FocusedPoster since it already
    /// carries everything a slide needs to render and link.
    let items: [FocusedPoster]

    /// The slide currently centered (drives the page dots and auto-advance).
    @State private var index = 0
    @FocusState private var focusedIndex: Int?
    @State private var autoAdvance: Task<Void, Never>?

    private let bannerHeight: CGFloat = 480
    private let rotation: Duration = .seconds(7)

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(spacing: 0) {
                    ForEach(Array(items.enumerated()), id: \.element.postID) { i, item in
                        NavigationLink(value: DeepLinkDestination.post(id: item.postID, autoplay: false)) {
                            HeroSlide(item: item, focused: focusedIndex == i)
                        }
                        .buttonStyle(.plain)   // Full-bleed slide draws its own focus ring.
                        .focused($focusedIndex, equals: i)
                        .containerRelativeFrame(.horizontal)
                        .id(i)
                        .accessibilityIdentifier("featured-slide")
                    }
                }
            }
            .scrollTargetBehavior(.paging)
            .scrollClipDisabled()   // let the focused slide's slight lift escape bounds
            .frame(height: bannerHeight)
            .overlay(alignment: .bottomTrailing) { pageDots }
            .focusSection()
            .onChange(of: focusedIndex) { _, new in
                // User moved into/through the hero: keep the dots in sync and
                // make sure the focused slide is centered.
                guard let new else { return }
                index = new
                withAnimation(.easeInOut(duration: 0.35)) { proxy.scrollTo(new, anchor: .center) }
            }
            .onChange(of: index) { _, new in
                // Auto-advance path (nothing focused): glide to the next slide.
                if focusedIndex == nil {
                    withAnimation(.easeInOut(duration: 0.6)) { proxy.scrollTo(new, anchor: .center) }
                }
            }
            .onAppear { startAutoAdvance() }
            .onDisappear { autoAdvance?.cancel() }
        }
    }

    @ViewBuilder
    private var pageDots: some View {
        if items.count > 1 {
            HStack(spacing: 10) {
                ForEach(items.indices, id: \.self) { i in
                    Circle()
                        .fill(i == index ? Color.white : Color.white.opacity(0.35))
                        .frame(width: 10, height: 10)
                }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 12)
            .background(.black.opacity(0.35), in: Capsule())
            .padding(.trailing, 90)
            .padding(.bottom, 24)
        }
    }

    /// Advance every `rotation` while the user isn't interacting with the hero,
    /// so it reads as a slideshow but never moves under a focused slide.
    private func startAutoAdvance() {
        guard items.count > 1 else { return }
        autoAdvance?.cancel()
        autoAdvance = Task { @MainActor in
            while !Task.isCancelled {
                try? await Task.sleep(for: rotation)
                if Task.isCancelled { return }
                guard focusedIndex == nil else { continue }
                index = (index + 1) % items.count
            }
        }
    }
}

// MARK: - Slide

private struct HeroSlide: View {

    let item: FocusedPoster
    let focused: Bool

    private let corner: CGFloat = 24

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            backdrop

            // Bottom scrim so the title stays legible over busy art.
            LinearGradient(
                colors: [.black.opacity(0.9), .black.opacity(0.35), .clear],
                startPoint: .bottom,
                endPoint: .top
            )
            // Leading scrim darkens the left where the text sits.
            LinearGradient(
                colors: [.black.opacity(0.85), .black.opacity(0.3), .clear],
                startPoint: .leading,
                endPoint: .trailing
            )

            textOverlay
                .padding(.horizontal, 56)
                .padding(.bottom, 48)
        }
        .frame(maxWidth: .infinity)
        .frame(height: 480)
        .clipShape(RoundedRectangle(cornerRadius: corner, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: corner, style: .continuous)
                .strokeBorder(.white.opacity(focused ? 0.9 : 0), lineWidth: 4)
        }
        .padding(.horizontal, 60)
        .scaleEffect(focused ? 1.02 : 1.0)
        .shadow(color: .black.opacity(focused ? 0.5 : 0), radius: 24, y: 10)
        .animation(.easeInOut(duration: 0.2), value: focused)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityLabel)
    }

    @ViewBuilder
    private var backdrop: some View {
        if let url = item.heroImageURL {
            LazyImage(url: url) { state in
                if let image = state.image {
                    image.resizable().aspectRatio(contentMode: .fill)
                } else {
                    PatreonColors.cardSurface
                }
            }
        } else {
            LinearGradient(
                colors: [PatreonColors.cardSurface, PatreonColors.background],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        }
    }

    private var textOverlay: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("FEATURED")
                .font(.caption.weight(.bold))
                .tracking(2)
                .foregroundStyle(.white.opacity(0.7))

            if let title = item.title {
                Text(title)
                    .font(.system(size: 60, weight: .bold))
                    .foregroundStyle(.white)
                    .lineLimit(2)
                    .minimumScaleFactor(0.6)
                    .shadow(color: .black.opacity(0.5), radius: 8, y: 2)
            }

            HStack(spacing: 14) {
                if item.isPaid {
                    Text("PATRON")
                        .font(.caption.weight(.bold))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 4)
                        .background(PatreonColors.brand.opacity(0.95))
                        .foregroundStyle(.white)
                        .clipShape(Capsule())
                }
                if let creator = item.creatorName {
                    Text(creator)
                        .font(.title3)
                        .foregroundStyle(.white.opacity(0.85))
                }
            }
        }
        .frame(maxWidth: 1100, alignment: .leading)
    }

    private var accessibilityLabel: String {
        let title = item.title ?? "Featured post"
        let creator = item.creatorName.map { " by \($0)" } ?? ""
        let paid = item.isPaid ? ", patron-only" : ""
        return "Featured: \(title)\(creator)\(paid)"
    }
}
