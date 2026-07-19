//
//  UpNextOverlayView.swift
//  PatreonTV
//
//  Netflix-style "Up Next" card shown over the player when an item finishes.
//  With autoplay enabled it counts down and auto-advances; otherwise it waits
//  for the user. Escapable at all times (FOCUS rules: no traps).
//

import NukeUI
import SwiftUI

struct UpNextOverlayView: View {

    let post: Post
    let creatorName: String?
    /// Seconds until auto-advance; nil disables the countdown ("Autoplay next"
    /// setting off).
    let countdownSeconds: Int?
    let onPlay: () -> Void
    let onDismiss: () -> Void

    @State private var remaining: Int = .max
    @Namespace private var focusNamespace

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            // Dim the (ended) video behind so the card reads at 10 feet.
            LinearGradient(
                colors: [.clear, .black.opacity(0.85)],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()
            .allowsHitTesting(false)

            card
                .padding(.trailing, 80)
                .padding(.bottom, 80)
        }
        // Claim focus from the (ended) player so the buttons are usable.
        .focusScope(focusNamespace)
        .task {
            guard let total = countdownSeconds else { return }
            remaining = total
            while remaining > 0 {
                try? await Task.sleep(for: .seconds(1))
                guard !Task.isCancelled else { return }
                remaining -= 1
            }
            onPlay()
        }
    }

    private var card: some View {
        HStack(alignment: .center, spacing: 32) {
            poster

            VStack(alignment: .leading, spacing: 10) {
                Text(countdownLabel)
                    .font(.caption.weight(.bold))
                    .foregroundStyle(PatreonColors.brand)
                    .textCase(.uppercase)

                Text(post.attributes.title ?? "Untitled")
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(.white)
                    .lineLimit(2)

                if let creatorName {
                    Text(creatorName)
                        .font(.body)
                        .foregroundStyle(.white.opacity(0.65))
                        .lineLimit(1)
                }

                HStack(spacing: 16) {
                    Button(action: onPlay) {
                        Label("Play Now", systemImage: "play.fill")
                            .font(.body.weight(.semibold))
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(PatreonColors.brand)
                    .prefersDefaultFocus(in: focusNamespace)

                    Button("Dismiss", action: onDismiss)
                        .buttonStyle(.bordered)
                }
                .padding(.top, 8)
            }
            .frame(maxWidth: 560, alignment: .leading)
        }
        .padding(28)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 24))
        .accessibilityElement(children: .contain)
        .accessibilityLabel(accessibilitySummary)
    }

    @ViewBuilder
    private var poster: some View {
        LazyImage(url: post.attributes.posterImageURL) { state in
            if let image = state.image {
                image.resizable().aspectRatio(contentMode: .fill)
            } else {
                ZStack {
                    PatreonColors.cardSurface
                    Image(systemName: post.attributes.postType.iconName)
                        .font(.system(size: 40))
                        .foregroundStyle(PatreonColors.tertiaryText)
                }
            }
        }
        .frame(width: 280, height: 158)
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .accessibilityHidden(true)
    }

    private var countdownLabel: String {
        if countdownSeconds != nil, remaining != .max, remaining >= 0 {
            return "Up Next in \(remaining)s"
        }
        return "Up Next"
    }

    private var accessibilitySummary: String {
        var parts = ["Up next: \(post.attributes.title ?? "Untitled")"]
        if let creatorName { parts.append("from \(creatorName)") }
        if countdownSeconds != nil { parts.append("playing automatically in \(remaining) seconds") }
        return parts.joined(separator: ", ")
    }
}
