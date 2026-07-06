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

    var body: some View {
        NavigationStack {
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
    }

    @ViewBuilder
    private var loadedContent: some View {
        ScrollView(.vertical, showsIndicators: false) {
            LazyVStack(alignment: .leading, spacing: 60, pinnedViews: []) {
                HeroBand(fallback: vm.heroFallback)
                    .padding(.bottom, -80)   // Let the first shelf overlap the gradient

                if !vm.continueWatching.isEmpty {
                    Shelf(
                        title: "Continue Watching",
                        posts: vm.continueWatching,
                        campaignFor: { vm.campaign(for: $0) }
                    )
                }

                if !vm.newFromCreators.isEmpty {
                    Shelf(
                        title: "New from Your Creators",
                        posts: vm.newFromCreators,
                        campaignFor: { vm.campaign(for: $0) }
                    )
                }

                if !vm.homeFeed.isEmpty {
                    Shelf(
                        title: "Home Feed",
                        posts: vm.homeFeed,
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
