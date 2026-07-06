//
//  HTMLRenderer.swift
//  PatreonTV
//
//  Converts the HTML in Patreon post content and campaign summaries into
//  either plain text (fallback) or a SwiftUI AttributedString (preferred).
//
//  Patreon post HTML is limited — mostly <p>, <br>, <a>, <strong>, <em>,
//  <ul>/<ol>/<li>. Everything else we strip.
//

import Foundation
import SwiftUI

enum HTMLRenderer {

    /// Convert Patreon post HTML into an AttributedString. Rendering
    /// happens via Foundation's built-in Markdown parser after we hand-
    /// convert HTML tags to Markdown. Cheap, deterministic, and doesn't
    /// require WebKit.
    static func attributedString(from html: String) -> AttributedString {
        let markdown = markdownFromHTML(html)
        // Options: allow inline formatting; preserve line breaks.
        var options = AttributedString.MarkdownParsingOptions()
        options.interpretedSyntax = .inlineOnlyPreservingWhitespace
        options.allowsExtendedAttributes = false
        if let attributed = try? AttributedString(markdown: markdown, options: options) {
            return attributed
        }
        return AttributedString(stripToPlainText(html))
    }

    /// Plain-text version — used for accessibility labels or when we don't
    /// want any styling. Same normalization as attributedString(from:) but
    /// tags removed.
    static func stripToPlainText(_ html: String) -> String {
        var s = html
        s = normalizeWhitespaceTags(in: s)
        s = s.replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
        s = unescapeEntities(in: s)
        return s.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    // MARK: - Internals

    /// Convert supported HTML tags into equivalent Markdown syntax.
    private static func markdownFromHTML(_ html: String) -> String {
        var s = html

        // Normalize whitespace-tag equivalents first.
        s = normalizeWhitespaceTags(in: s)

        // Links: <a href="url">text</a>  →  [text](url)
        // Non-greedy match, tolerate href with single or double quotes.
        let linkPattern = #"<a[^>]*href=[\"']([^\"']+)[\"'][^>]*>(.*?)</a>"#
        if let regex = try? NSRegularExpression(pattern: linkPattern,
                                                options: [.caseInsensitive, .dotMatchesLineSeparators]) {
            let range = NSRange(s.startIndex..., in: s)
            s = regex.stringByReplacingMatches(in: s, options: [], range: range,
                                               withTemplate: "[$2]($1)")
        }

        // Bold: <strong>…</strong>  or  <b>…</b>  → **…**
        s = s.replacingOccurrences(of: "</?strong>", with: "**", options: [.regularExpression, .caseInsensitive])
        s = s.replacingOccurrences(of: "</?b>", with: "**", options: [.regularExpression, .caseInsensitive])

        // Italic: <em>…</em>  or  <i>…</i>  → *…*
        s = s.replacingOccurrences(of: "</?em>", with: "*", options: [.regularExpression, .caseInsensitive])
        s = s.replacingOccurrences(of: "</?i>", with: "*", options: [.regularExpression, .caseInsensitive])

        // Lists: keep the bullet, drop the tags. This isn't perfect but
        // interpretedSyntax = .inlineOnlyPreservingWhitespace ignores
        // block-level Markdown anyway; users see plain lines with dashes.
        s = s.replacingOccurrences(of: "<li[^>]*>", with: "\n• ", options: [.regularExpression, .caseInsensitive])
        s = s.replacingOccurrences(of: "</li>", with: "", options: [.regularExpression, .caseInsensitive])
        s = s.replacingOccurrences(of: "</?[uo]l[^>]*>", with: "\n", options: [.regularExpression, .caseInsensitive])

        // Strip any remaining tags — we ignore <img>, <table>, <hr>, etc.
        s = s.replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)

        // Unescape entities last so a "&lt;" inside content doesn't get
        // re-interpreted as a tag by earlier substitutions.
        s = unescapeEntities(in: s)

        // Collapse runs of 3+ newlines to 2 (single blank line).
        s = s.replacingOccurrences(of: "\n{3,}", with: "\n\n", options: .regularExpression)

        return s.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Turn HTML paragraph and break tags into whitespace so that later
    /// tag-stripping produces readable text.
    private static func normalizeWhitespaceTags(in html: String) -> String {
        var s = html
        s = s.replacingOccurrences(of: "<br\\s*/?>", with: "\n", options: [.regularExpression, .caseInsensitive])
        s = s.replacingOccurrences(of: "</p>", with: "\n\n", options: [.regularExpression, .caseInsensitive])
        s = s.replacingOccurrences(of: "<p[^>]*>", with: "", options: [.regularExpression, .caseInsensitive])
        return s
    }

    private static let entities: [(String, String)] = [
        ("&nbsp;", " "),
        ("&amp;", "&"),
        ("&lt;", "<"),
        ("&gt;", ">"),
        ("&quot;", "\""),
        ("&apos;", "'"),
        ("&#39;", "'"),
        ("&hellip;", "…"),
        ("&mdash;", "—"),
        ("&ndash;", "–"),
        ("&ldquo;", "“"),
        ("&rdquo;", "”"),
        ("&lsquo;", "‘"),
        ("&rsquo;", "’"),
    ]

    private static func unescapeEntities(in s: String) -> String {
        var out = s
        for (from, to) in entities {
            out = out.replacingOccurrences(of: from, with: to)
        }
        // Numeric entities: &#123;
        if let regex = try? NSRegularExpression(pattern: "&#(\\d+);") {
            var result = ""
            var lastEnd = out.startIndex
            let range = NSRange(out.startIndex..., in: out)
            regex.enumerateMatches(in: out, options: [], range: range) { match, _, _ in
                guard let match, match.numberOfRanges == 2,
                      let full = Range(match.range, in: out),
                      let numRange = Range(match.range(at: 1), in: out),
                      let code = UInt32(out[numRange]),
                      let scalar = Unicode.Scalar(code)
                else { return }
                result.append(contentsOf: out[lastEnd..<full.lowerBound])
                result.append(Character(scalar))
                lastEnd = full.upperBound
            }
            result.append(contentsOf: out[lastEnd..<out.endIndex])
            out = result
        }
        return out
    }
}
