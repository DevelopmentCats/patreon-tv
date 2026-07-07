//
//  HomeView.swift
//  PatreonTV
//
//  The couch-first landing screen. Structure follows Swiftfin's cinematic
//  pattern: hero art at the top that follows the focused poster, then a
//  vertical stack of horizontal shelves below.
//
//  See references/swiftfin_code/CinematicItemSelector.swift for the pattern.
//

import SwiftUI

struct HomeView: View {

    @State private var vm = HomeViewModel()
    @State private var prefs = ContentPreferences.shared
    @Environment(DeepLinkRouter.self) private var router

    /// Applies the mature-content gate to a shelf's posts based on each post's
    /// owning campaign. Keeps posts whose campaign is unknown (assumed safe).
    private func visible(_ posts: [Post]) -> [Post] {
        if prefs.showMatureContent { return posts }
        return posts.filter { vm.campaign(for: $0)?.attributes.isNSFW != true }
    }

    /// The hero fallback, suppressed when the top post is from a hidden NSFW
    /// creator so mature art doesn't flash before the user focuses a card.
    private var heroFallback: FocusedPoster? {
        guard let fb = vm.heroFallback else { return nil }
        if prefs.showMatureContent { return fb }
        if let first = vm.homeFeed.first, vm.campaign(for: first)?.attributes.isNSFW == true {
            return nil
        }
        return fb
    }

    var body: some View {
        // No NavigationStack here — HomeShell already wraps the Home tab in one.
        // Nesting a second NavigationStack trapped upward focus so the tab bar
        // became unreachable once focus moved into the shelves.
        Group {
            switch vm.state {
            case .idle, .loading:
                ProgressView()
                    .controlSize(.large)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            case .empty:
                EmptyFeedView()
            case .loaded:
                loadedContent
            case .error(let message):
                ErrorView(message: message) { Task { await vm.reload() } }
            }
        }
        .task { await vm.load() }
        .background(PatreonColors.background.ignoresSafeArea())
    }

    @ViewBuilder
    private var loadedContent: some View {
        let continueWatching = visible(vm.continueWatching)
        let feed = visible(vm.homeFeed)

        // Plain VStack (not Lazy): tvOS won't render/focus below-the-fold
        // children of a LazyVStack. Shelves inside stay lazy via LazyHStack.
        ScrollView(.vertical, showsIndicators: false) {
            VStack(alignment: .leading, spacing: 40) {
                // Canonical tvOS hero: takes ~80% of the viewport with a
                // .focusSection() so the first shelf peeks below and focus can
                // travel back up through it to the tab bar.
                HeroBand(fallback: heroFallback)
                    .frame(maxWidth: .infinity, alignment: .leading)

                // A visible, focusable "Play featured" row between the hero and
                // the shelves. It's the focus stepping-stone that lets "up" from
                // the first shelf reach here, then continue to the tab bar.
                if let featured = heroFallback {
                    Button {
                        router.pending = .post(id: featured.postID, autoplay: true)
                    } label: {
                        Label("Play", systemImage: "play.fill")
                            .font(.title3.weight(.semibold))
                            .padding(.horizontal, 44)
                            .padding(.vertical, 16)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(PatreonColors.brand)
                    .padding(.leading, 60)
                }

                if !continueWatching.isEmpty {
                    Shelf(
                        title: "Continue Watching",
                        posts: continueWatching,
                        campaignFor: { vm.campaign(for: $0) }
                    )
                }

                if !feed.isEmpty {
                    Shelf(
                        title: "New from Your Creators",
                        posts: feed,
                        campaignFor: { vm.campaign(for: $0) },
                        onNearEnd: { post in
                            Task { await vm.loadMoreIfNeeded(current: post) }
                        }
                    )
                }
            }
            .padding(.bottom, 40)
        }
        .scrollClipDisabled()   // tvOS 17+ — lets focused-card scale escape ScrollView bounds
    }
}

struct EmptyFeedView: View {
    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "sparkles")
                .font(.system(size: 80))
                .foregroundStyle(PatreonColors.secondaryText)
            Text("Nothing here yet")
                .font(.title2)
                .foregroundStyle(PatreonColors.primaryText)
            Text("Support a creator on Patreon to see their posts here.")
                .foregroundStyle(PatreonColors.secondaryText)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

struct ErrorView: View {
    let message: String
    let retry: () -> Void

    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 60))
                .foregroundStyle(.orange)
            Text(message)
                .font(.title3)
                .foregroundStyle(PatreonColors.primaryText)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 800)
            Button("Try Again", action: retry)
                .buttonStyle(.borderedProminent)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
