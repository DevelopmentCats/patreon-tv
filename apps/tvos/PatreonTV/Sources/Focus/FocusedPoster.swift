//
//  FocusedPoster.swift
//  PatreonTV
//
//  Propagates the currently-focused post up the view hierarchy via
//  @FocusedValue, so a hero band elsewhere on the screen can reflect it.
//
//  Pattern from references/swiftfin_code/CinematicItemSelector.swift.
//

import SwiftUI

/// A lightweight identity-preserving wrapper — @FocusedValue values must be
/// Equatable, and we don't want to leak the whole Post struct through the
/// focus environment.
struct FocusedPoster: Equatable {
    let postID: String
    let title: String?
    let heroImageURL: URL?
    let creatorName: String?
    let campaignID: String?
    let publishedAt: String?
    let isPaid: Bool
}

private struct FocusedPosterKey: FocusedValueKey {
    typealias Value = FocusedPoster
}

extension FocusedValues {
    /// The most-recently-focused poster in the current focus scope.
    /// Read via `@FocusedValue(\.focusedPoster)`.
    var focusedPoster: FocusedPoster? {
        get { self[FocusedPosterKey.self] }
        set { self[FocusedPosterKey.self] = newValue }
    }
}
