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
                        NavigationLink {
                            PostDetailView(postID: post.id)
                        } label: {
                            PostCard(post: post)
                        }
                        .buttonStyle(.card)   // Native tvOS focus effect (parallax + lift)
                    }
                }
                .padding(.horizontal, 60)
                .padding(.vertical, 30)   // Breathing room for focused-card scale
            }
            .scrollClipDisabled()
        }
        .focusSection()
    }
}
