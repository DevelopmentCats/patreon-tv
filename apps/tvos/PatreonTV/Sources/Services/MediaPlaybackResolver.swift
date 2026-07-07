//
//  MediaPlaybackResolver.swift
//  PatreonTV
//
//  Picks the best playable URL from a post document. Both Mux (stream.mux.com)
//  and Patreon (patreonusercontent.com) media URLs are self-signed with an
//  expiring token in the query string, so no cookies or per-request auth are
//  needed — verified against a live audio post — and everything plays direct.
//

import Foundation
import os.log

enum MediaPlaybackSource: Sendable, Identifiable {
    case direct(URL)

    var id: String { url.absoluteString }
    var url: URL { switch self { case .direct(let u): u } }
}

enum MediaPlaybackResolver {

    private static let log = Logger(subsystem: "com.patreontv.PatreonTV", category: "Playback")

    static func resolve(from doc: SingleResource<Post>) -> MediaPlaybackSource? {
        var best: (score: Int, url: URL)?

        for inc in doc.included ?? [] {
            guard case .media(let media) = inc else { continue }

            if let url = media.attributes.display?.url {
                consider(url: url, mimetype: media.attributes.mimetype, label: "display", best: &best)
            }
            if let url = media.attributes.downloadURL {
                consider(url: url, mimetype: media.attributes.mimetype, label: "download", best: &best)
            }
        }

        guard let best else { return nil }

        log.info("Selected playback URL host=\(best.url.host ?? "?") ext=\(best.url.pathExtension)")
        return .direct(best.url)
    }

    private static func consider(
        url: URL,
        mimetype: String?,
        label: String,
        best: inout (score: Int, url: URL)?
    ) {
        let score = score(url: url, mimetype: mimetype, label: label)
        guard score > 0 else { return }
        if best == nil || score > best!.score {
            best = (score, url)
        }
    }

    private static func score(url: URL, mimetype: String?, label: String) -> Int {
        if mimetype?.hasPrefix("image/") == true { return 0 }

        var score = 0
        let host = url.host()?.lowercased() ?? ""
        let ext = url.pathExtension.lowercased()

        if label == "display" { score += 40 }
        if host.contains("stream.mux.com") { score += 100 }
        if ext == "m3u8" || ext == "m3u" { score += 80 }
        if mimetype == "application/x-mpegURL" || mimetype == "application/vnd.apple.mpegurl" { score += 60 }
        if mimetype?.hasPrefix("video/") == true { score += 30 }
        if host.contains("patreonusercontent.com") { score += 10 }
        return score
    }
}
