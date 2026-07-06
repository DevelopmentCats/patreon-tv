//
//  DeepLinkRouter.swift
//  PatreonTV
//
//  Handles patreontv:// URLs from the Top Shelf extension and system opens.
//
//  Recognized URL shapes:
//    patreontv://post/<id>          — open the post detail
//    patreontv://post/<id>/play     — open the post detail and auto-play
//    patreontv://creator/<id>       — open the creator detail
//

import Foundation
import Observation

@Observable
@MainActor
final class DeepLinkRouter {

    enum Destination: Equatable {
        case post(id: String, autoplay: Bool)
        case creator(id: String)
    }

    /// The most recently requested destination. Views observe this and
    /// clear it (set to nil) after navigation completes.
    var pending: Destination?

    func handle(url: URL) {
        guard url.scheme == "patreontv" else { return }

        // URLComponents on a custom scheme URL puts the "authority" (post/creator)
        // in `host` and the rest in `path`.
        guard let comps = URLComponents(url: url, resolvingAgainstBaseURL: false),
              let host = comps.host
        else { return }

        let pathSegments = comps.path.split(separator: "/").map(String.init)

        switch host {
        case "post":
            guard let id = pathSegments.first, !id.isEmpty else { return }
            let autoplay = pathSegments.contains("play")
            pending = .post(id: id, autoplay: autoplay)
        case "creator":
            guard let id = pathSegments.first, !id.isEmpty else { return }
            pending = .creator(id: id)
        default:
            return
        }
    }

    func consume() {
        pending = nil
    }
}
