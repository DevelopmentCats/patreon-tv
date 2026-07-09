//
//  ChapterParser.swift
//  PatreonTV
//
//  Patreon's API exposes no chapter data, but podcast-style posts routinely
//  embed a timestamp list in the description ("0:00 Intro", "12:34 – Topic").
//  This parser lifts those lines into Chapter values so the player can build
//  native navigation markers.
//

import Foundation

struct Chapter: Equatable, Sendable {
    let title: String
    let startSeconds: Double
}

enum ChapterParser {

    /// Matches a line-leading timestamp — `M:SS`, `MM:SS`, or `H:MM:SS`,
    /// optionally wrapped in ()/[] — followed by a separator and a title.
    private static let lineRegex = try! NSRegularExpression(
        pattern: #"^\s*[\(\[]?(?:(\d{1,2}):)?(\d{1,3}):(\d{2})[\)\]]?\s*[-–—:.]?\s*(\S.*)$"#
    )

    /// Extract chapters from post content HTML. Returns [] unless at least
    /// two chapters parse with strictly ascending timestamps — a single
    /// timestamp is more likely a reference ("see 12:30") than a chapter list.
    /// Chapters past `duration` (when known) are dropped.
    static func chapters(fromHTML html: String, duration: Double? = nil) -> [Chapter] {
        let text = HTMLRenderer.stripToPlainText(html)
        var found: [Chapter] = []

        for line in text.components(separatedBy: .newlines) {
            guard let chapter = parse(line: line) else { continue }
            if let duration, chapter.startSeconds > duration { continue }
            // Enforce ascending order; a non-ascending timestamp means this
            // isn't a chapter list (or the list ended).
            if let last = found.last, chapter.startSeconds <= last.startSeconds { continue }
            found.append(chapter)
        }

        return found.count >= 2 ? found : []
    }

    private static func parse(line: String) -> Chapter? {
        let range = NSRange(line.startIndex..., in: line)
        guard let match = lineRegex.firstMatch(in: line, range: range) else { return nil }

        func group(_ i: Int) -> String? {
            guard match.range(at: i).location != NSNotFound,
                  let r = Range(match.range(at: i), in: line)
            else { return nil }
            return String(line[r])
        }

        let hours = group(1).flatMap(Double.init) ?? 0
        guard let minutes = group(2).flatMap(Double.init),
              let seconds = group(3).flatMap(Double.init),
              seconds < 60,
              var title = group(4)
        else { return nil }
        // Without an hours group, minutes may exceed 59 ("90:00" = 1.5h).
        if hours > 0, minutes >= 60 { return nil }

        // Trim leftover separators and surrounding punctuation from the title.
        title = title.trimmingCharacters(in: CharacterSet(charactersIn: " -–—:.\t"))
        guard !title.isEmpty else { return nil }

        return Chapter(title: title, startSeconds: hours * 3600 + minutes * 60 + seconds)
    }
}
