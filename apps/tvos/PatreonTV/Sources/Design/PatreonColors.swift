//
//  PatreonColors.swift
//  PatreonTV
//
//  Brand + neutral palette. Kept small and centralized so the whole app can
//  pivot to a new accent without a global search.
//

import SwiftUI

enum PatreonColors {

    /// Patreon coral. Used sparingly — primarily for the sign-in CTA and
    /// focused-item accent glow.
    static let brand = Color(red: 0.98, green: 0.31, blue: 0.30)

    /// The living-room-safe background. Almost-black rather than pure black
    /// to reduce eye fatigue and to give video hero art a color to blend into.
    static let background = Color(red: 0.04, green: 0.04, blue: 0.06)

    /// Card surface for post cards on non-hero rows.
    static let cardSurface = Color(red: 0.10, green: 0.10, blue: 0.13)

    /// Primary text on background.
    static let primaryText = Color.white

    /// Secondary text (metadata, timestamps).
    static let secondaryText = Color.white.opacity(0.65)

    /// Tertiary text (rare — footnotes).
    static let tertiaryText = Color.white.opacity(0.4)
}
