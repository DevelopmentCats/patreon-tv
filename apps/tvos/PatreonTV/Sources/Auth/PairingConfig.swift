//
//  PairingConfig.swift
//  PatreonTV
//
//  Base URL for the device-link pairing service (Cloudflare Pages Functions).
//  Not hardcoded — read from the `PairingBaseURL` Info.plist key, which is
//  populated from the `PAIRING_BASE_URL` build setting per configuration
//  (Debug → local wrangler, Release → https://patreontv.com). See project.yml.
//

import Foundation

enum PairingConfig {
    /// Pairing API origin, resolved from the build configuration.
    static var baseURL: URL {
        if let raw = Bundle.main.object(forInfoDictionaryKey: "PairingBaseURL") as? String,
           !raw.isEmpty,
           let url = URL(string: raw) {
            return url
        }
        // Safety fallback if the build setting is missing.
        return URL(string: "https://patreontv.com")!
    }
}
