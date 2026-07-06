//
//  HeroBand.swift
//  PatreonTV
//
//  The big background band at the top of Home that reflects the
//  currently-focused post. Debounces changes to prevent flicker as the
//  user scrolls through a shelf.
//
//  Pattern based on references/swiftfin_code/CinematicItemSelector.swift
//  (Swiftfin's CinematicScrollView).
//

import NukeUI
import SwiftUI

struct HeroBand: View {

    /// The default poster to show if nothing is focused yet.
    let fallback: FocusedPoster?

    @FocusedValue(\.focusedPoster) private var focused

    /// Debounced value — updates 500ms after focus settles.
    @State private var displayed: FocusedPoster?

    /// Task handle for the debounce timer so we can cancel it on quick moves.
    @State private var debounceTask: Task<Void, Never>?

    private let debounce: Duration = .milliseconds(500)

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            backgroundImage
                .transition(.opacity.animation(.easeInOut(duration: 0.35)))
                .id(displayed?.postID ?? "empty")

            LinearGradient(
                colors: [
                    Color.black.opacity(0.9),
                    Color.black.opacity(0.4),
                    Color.clear,
                ],
                startPoint: .bottom,
                endPoint: .top
            )

            textOverlay
                .padding(.horizontal, 60)
                .padding(.bottom, 60)
        }
        .frame(height: 640)
        .frame(maxWidth: .infinity)
        .clipped()
        .onAppear { displayed = fallback }
        .onChange(of: focused) { _, newValue in
            debounceTask?.cancel()
            guard let newValue else { return }
            debounceTask = Task { @MainActor in
                try? await Task.sleep(for: debounce)
                if Task.isCancelled { return }
                withAnimation(.easeInOut(duration: 0.35)) {
                    displayed = newValue
                }
            }
        }
    }

    @ViewBuilder
    private var backgroundImage: some View {
        if let url = displayed?.heroImageURL {
            LazyImage(url: url) { state in
                if let image = state.image {
                    image
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                } else {
                    PatreonColors.background
                }
            }
        } else {
            PatreonColors.background
        }
    }

    @ViewBuilder
    private var textOverlay: some View {
        if let d = displayed {
            VStack(alignment: .leading, spacing: 12) {
                if d.isPaid {
                    Text("PATRON")
                        .font(.caption.weight(.bold))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 4)
                        .background(PatreonColors.brand.opacity(0.95))
                        .foregroundStyle(.white)
                        .clipShape(Capsule())
                }
                if let title = d.title {
                    Text(title)
                        .font(.system(size: 64, weight: .bold))
                        .foregroundStyle(.white)
                        .lineLimit(2)
                        .shadow(color: .black.opacity(0.5), radius: 8, y: 2)
                }
                if let creator = d.creatorName {
                    Text(creator)
                        .font(.title3)
                        .foregroundStyle(.white.opacity(0.85))
                }
            }
            .frame(maxWidth: 1200, alignment: .leading)
            .transition(.opacity.combined(with: .move(edge: .bottom)))
        }
    }
}
