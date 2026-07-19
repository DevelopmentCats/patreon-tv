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

    /// Applies the mature-content gate to a shelf's posts based on each post's
    /// owning campaign. Keeps posts whose campaign is unknown (assumed safe).
    private func visible(_ posts: [Post]) -> [Post] {
        if prefs.showMatureContent { return posts }
        return posts.filter { vm.campaign(for: $0)?.attributes.isNSFW != true }
    }

    /// Slides for the featured carousel: the newest visible posts, mapped to
    /// the lightweight FocusedPoster the hero renders. NSFW gating is inherited
    /// from `visible`, so mature art never appears while the toggle is off.
    private var featuredItems: [FocusedPoster] {
        visible(vm.homeFeed).prefix(6).map { post in
            let campaign = vm.campaign(for: post)
            return FocusedPoster(
                postID: post.id,
                title: post.attributes.title,
                heroImageURL: post.attributes.posterImageURL,
                creatorName: campaign?.attributes.name,
                campaignID: campaign?.id,
                publishedAt: post.attributes.publishedAt,
                isPaid: post.attributes.isPaid ?? false
            )
        }
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
                // The featured carousel is a full-width focus section pinned
                // above the shelves. Because it always holds a focusable slide,
                // swiping up from any shelf reliably lands here, and one more
                // swipe up reveals the tab bar — no dependence on a conditional
                // Play pill or TabView's finicky top-edge escape.
                if !featuredItems.isEmpty {
                    FeaturedHero(items: featuredItems)
                }

                if !continueWatching.isEmpty {
                    Shelf(
                        title: "Continue Watching",
                        posts: continueWatching,
                        campaignFor: { vm.campaign(for: $0) }
                    )
                }

                // Short merged shelf of the latest posts across creators; the
                // per-creator rows below carry the depth.
                if !feed.isEmpty {
                    Shelf(
                        title: "New from Your Creators",
                        posts: Array(feed.prefix(10)),
                        campaignFor: { vm.campaign(for: $0) }
                    )
                }

                ForEach(creatorRows) { row in
                    Shelf(
                        title: row.campaign.attributes.name ?? "Creator",
                        posts: row.posts,
                        campaignFor: { _ in row.campaign },
                        onNearEnd: { post in
                            Task { await vm.loadMoreCreatorRow(campaignID: row.id, current: post) }
                        },
                        headerLink: .creator(id: row.campaign.id),
                        headerAvatarURL: row.campaign.attributes.bestAvatarURL
                    )
                }
            }
            .padding(.bottom, 40)
        }
        .scrollClipDisabled()   // tvOS 17+ — lets focused-card scale escape ScrollView bounds
    }

    /// Creator rows with content, honoring the mature-content gate.
    private var creatorRows: [HomeViewModel.CreatorRow] {
        vm.creatorRows.filter { row in
            guard !row.posts.isEmpty else { return false }
            if prefs.showMatureContent { return true }
            return row.campaign.attributes.isNSFW != true
        }
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
