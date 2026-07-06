//
//  HTMLRendererTests.swift
//  PatreonTVTests
//
//  Exercise the HTML → AttributedString / plain-text conversion against the
//  kinds of markup Patreon posts actually contain.
//

import XCTest
@testable import PatreonTV

final class HTMLRendererTests: XCTestCase {

    // MARK: - stripToPlainText

    func test_strip_paragraphs_and_breaks() {
        let html = "<p>First paragraph.</p><p>Second<br>line break inside.</p>"
        let plain = HTMLRenderer.stripToPlainText(html)
        XCTAssertTrue(plain.contains("First paragraph."))
        XCTAssertTrue(plain.contains("Second"))
        XCTAssertTrue(plain.contains("line break inside."))
    }

    func test_strip_removes_all_tags() {
        let html = "<div class='x'><span>Inline</span> then <strong>bold</strong>.</div>"
        let plain = HTMLRenderer.stripToPlainText(html)
        XCTAssertFalse(plain.contains("<"))
        XCTAssertFalse(plain.contains(">"))
        XCTAssertEqual(plain, "Inline then bold.")
    }

    func test_strip_unescapes_common_entities() {
        let html = "&lt;code&gt; &amp; &quot;text&quot; &nbsp; &#39;quote&#39;"
        let plain = HTMLRenderer.stripToPlainText(html)
        XCTAssertEqual(plain, "<code> & \"text\"   'quote'")
    }

    func test_strip_unescapes_numeric_entities() {
        let html = "&#8212; em dash &#233; e-acute"
        let plain = HTMLRenderer.stripToPlainText(html)
        XCTAssertTrue(plain.contains("—"))
        XCTAssertTrue(plain.contains("é"))
    }

    func test_strip_handles_empty_and_whitespace() {
        XCTAssertEqual(HTMLRenderer.stripToPlainText(""), "")
        XCTAssertEqual(HTMLRenderer.stripToPlainText("   \n  "), "")
        XCTAssertEqual(HTMLRenderer.stripToPlainText("<p></p>"), "")
    }

    // MARK: - attributedString

    func test_attributed_preserves_link_text() {
        let html = "<p>Visit <a href=\"https://example.com\">our site</a> today.</p>"
        let attr = HTMLRenderer.attributedString(from: html)
        // The plain-text projection should not contain the URL, only the label.
        let plain = String(attr.characters)
        XCTAssertTrue(plain.contains("our site"))
        XCTAssertTrue(plain.contains("Visit"))
        XCTAssertTrue(plain.contains("today"))
        XCTAssertFalse(plain.contains("https://example.com"),
                       "URL should be attached to the link run, not visible in plain text")
    }

    func test_attributed_preserves_bold_and_italic_text() {
        let html = "This is <strong>important</strong> and <em>subtle</em>."
        let attr = HTMLRenderer.attributedString(from: html)
        let plain = String(attr.characters)
        XCTAssertEqual(plain, "This is important and subtle.")
    }

    func test_attributed_handles_line_breaks_between_paragraphs() {
        let html = "<p>Line one.</p><p>Line two.</p>"
        let attr = HTMLRenderer.attributedString(from: html)
        let plain = String(attr.characters)
        XCTAssertTrue(plain.contains("Line one."))
        XCTAssertTrue(plain.contains("Line two."))
        XCTAssertTrue(plain.contains("\n"),
                      "Expected a newline between paragraphs; got: \(plain)")
    }

    func test_attributed_handles_lists() {
        let html = "<ul><li>Alpha</li><li>Beta</li><li>Gamma</li></ul>"
        let attr = HTMLRenderer.attributedString(from: html)
        let plain = String(attr.characters)
        XCTAssertTrue(plain.contains("Alpha"))
        XCTAssertTrue(plain.contains("Beta"))
        XCTAssertTrue(plain.contains("Gamma"))
    }

    func test_attributed_does_not_crash_on_malformed_html() {
        // Patreon HTML is generally well-formed but never trust it.
        let malformed = "<p>Unclosed <strong>bold <em>italic</p>"
        let attr = HTMLRenderer.attributedString(from: malformed)
        XCTAssertFalse(String(attr.characters).isEmpty)
    }

    func test_attributed_survives_apostrophe_in_link_text() {
        // Common Patreon pattern
        let html = "<p>Read <a href='https://example.com'>Sam's post</a>.</p>"
        let attr = HTMLRenderer.attributedString(from: html)
        XCTAssertTrue(String(attr.characters).contains("Sam"))
    }
}
