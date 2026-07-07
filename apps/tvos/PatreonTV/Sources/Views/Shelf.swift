//
//  Shelf.swift
//  PatreonTV
//
//  A horizontal shelf of posts. tvOS design rules FOCUS-02 (predictable
//  spatial movement), FOCUS-05 (minimum 250x150pt cards), FOCUS-09
//  (stable order).
//
//  Uses .focusSection() so vertical swipes move between shelves in the
//  parent VStack, and horizontal swipes move within this shelf.
//

import SwiftUI

struct Shelf: View {

    let title: String
    let posts: [Post]
    /// Optional lookup: given a post, return its owning Campaign. Enables
    /// creator names in the focused-poster metadata for the hero band.
    var campaignFor: ((Post) -> Campaign?)? = nil
    /// Called when the shelf's data source should page in more items — we pass
    /// the last-visible post so the caller can decide whether to fetch more.
    var onNearEnd: ((Post) -> Void)? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            Text(title)
                .font(.title2.weight(.semibold))
                .foregroundStyle(PatreonColors.primaryText)
                .padding(.horizontal, 60)
                .accessibilityAddTraits(.isHeader)

            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(spacing: 32) {
                    ForEach(posts) { post in
                        NavigationLink(value: DeepLinkDestination.post(id: post.id, autoplay: false)) {
                            PostCard(post: post, campaign: campaignFor?(post))
                        }
                        .buttonStyle(.card)   // Native tvOS focus effect (parallax + lift)
                        .focusedValue(\.focusedPoster, focusedPoster(for: post))
                        .onAppear {
                            // Cheap heuristic: if we're within 5 of the end,
                            // ask for more. Real prefetch policy lives in the
                            // view model.
                            if posts.suffix(5).contains(where: { $0.id == post.id }) {
                                onNearEnd?(post)
                            }
                        }
                    }
                }
                .padding(.horizontal, 60)
                .padding(.vertical, 30)   // Breathing room for focused-card scale
            }
            .scrollClipDisabled()
        }
        .focusSection()
    }

    private func focusedPoster(for post: Post) -> FocusedPoster {
        let campaign = campaignFor?(post)
        return FocusedPoster(
            postID: post.id,
            title: post.attributes.title,
            heroImageURL: post.attributes.posterImageURL,
            creatorName: campaign?.attributes.name,
            campaignID: campaign?.id ?? post.relationships?.campaign?.data?.id,
            publishedAt: post.attributes.publishedAt,
            isPaid: post.attributes.isPaid ?? false
        )
    }
}
