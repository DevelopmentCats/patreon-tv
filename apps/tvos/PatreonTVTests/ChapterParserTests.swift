//
//  ChapterParserTests.swift
//  PatreonTVTests
//
//  Timestamp-list mining from post HTML: formats, ordering, and the
//  two-chapter minimum that filters out incidental timestamps.
//

import XCTest
@testable import PatreonTV

final class ChapterParserTests: XCTestCase {

    func test_parses_basic_mm_ss_list() {
        let html = """
        <p>Episode notes</p>
        <p>0:00 Intro<br>5:30 Main topic<br>12:45 Wrap up</p>
        """
        let chapters = ChapterParser.chapters(fromHTML: html)
        XCTAssertEqual(chapters.count, 3)
        XCTAssertEqual(chapters[0], Chapter(title: "Intro", startSeconds: 0))
        XCTAssertEqual(chapters[1], Chapter(title: "Main topic", startSeconds: 330))
        XCTAssertEqual(chapters[2], Chapter(title: "Wrap up", startSeconds: 765))
    }

    func test_parses_h_mm_ss_and_separators() {
        let html = "<p>0:00 - Cold open<br>59:59 – Q&amp;A<br>1:02:03 — Finale</p>"
        let chapters = ChapterParser.chapters(fromHTML: html)
        XCTAssertEqual(chapters.count, 3)
        XCTAssertEqual(chapters[1].title, "Q&A")
        XCTAssertEqual(chapters[1].startSeconds, 3599)
        XCTAssertEqual(chapters[2].title, "Finale")
        XCTAssertEqual(chapters[2].startSeconds, 3723)
    }

    func test_parses_bracketed_timestamps() {
        let html = "<p>[0:00] Intro<br>(10:00) Discussion</p>"
        let chapters = ChapterParser.chapters(fromHTML: html)
        XCTAssertEqual(chapters.count, 2)
        XCTAssertEqual(chapters[1], Chapter(title: "Discussion", startSeconds: 600))
    }

    func test_single_timestamp_is_not_a_chapter_list() {
        let html = "<p>Big reveal at 12:30, don't miss it!</p><p>12:30 The reveal</p>"
        XCTAssertEqual(ChapterParser.chapters(fromHTML: html), [])
    }

    func test_requires_ascending_order() {
        // Descending timestamps are a reference list, not chapters.
        let html = "<p>10:00 Later bit<br>5:00 Earlier bit</p>"
        XCTAssertEqual(ChapterParser.chapters(fromHTML: html), [])
    }

    func test_drops_chapters_past_duration() {
        let html = "<p>0:00 Intro<br>5:00 Middle<br>90:00 Bogus</p>"
        let chapters = ChapterParser.chapters(fromHTML: html, duration: 600)
        XCTAssertEqual(chapters.map(\.title), ["Intro", "Middle"])
    }

    func test_ignores_prose_and_empty_titles() {
        let html = "<p>We start at noon. 0:00<br>1:00</p>"
        XCTAssertEqual(ChapterParser.chapters(fromHTML: html), [])
    }

    func test_no_chapters_in_plain_description() {
        let html = "<p>Thanks for watching this month's video! More soon.</p>"
        XCTAssertEqual(ChapterParser.chapters(fromHTML: html), [])
    }
}
