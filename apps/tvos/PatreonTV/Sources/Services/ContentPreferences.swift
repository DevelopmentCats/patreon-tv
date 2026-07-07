//
//  ContentPreferences.swift
//  PatreonTV
//
//  User-facing content settings, persisted in UserDefaults. Currently just the
//  mature-content gate: NSFW creators are hidden by default and revealed via a
//  Settings toggle.
//

import Foundation

@MainActor
@Observable
final class ContentPreferences {

    static let shared = ContentPreferences()

    private let matureKey = "show_mature_content"

    /// When false (default), NSFW creators are hidden from Creators and Search.
    var showMatureContent: Bool {
        didSet { UserDefaults.standard.set(showMatureContent, forKey: matureKey) }
    }

    private init() {
        showMatureContent = UserDefaults.standard.bool(forKey: matureKey)
    }
}
