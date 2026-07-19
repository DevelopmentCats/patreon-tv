//
//  HomeFocusUITests.swift
//  PatreonTVUITests
//
//  Reproduces the reported Home focus trap with real Siri Remote presses:
//  from a card in the first shelf, swiping up must eventually reach the top
//  tab bar (via the featured hero carousel). Runs fully offline against
//  GalleryMockURLProtocol (GALLERY_MOCK=1).
//

import XCTest

final class HomeFocusUITests: XCTestCase {

    override func setUp() {
        continueAfterFailure = false
    }

    private func launchHome() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchEnvironment["GALLERY_SCREEN"] = "home"
        app.launchEnvironment["GALLERY_MOCK"] = "1"
        app.launch()
        return app
    }

    /// Press a direction and give the focus engine time to settle + scroll.
    private func press(_ button: XCUIRemote.Button, times: Int = 1) {
        for _ in 0..<times {
            XCUIRemote.shared.press(button)
            usleep(400_000)   // 0.4s — focus animation + scroll settle
        }
    }

    /// Home is loaded once a featured hero slide exists.
    private func waitForHome(_ app: XCUIApplication) {
        let slide = app.buttons.matching(identifier: "featured-slide").firstMatch
        XCTAssertTrue(slide.waitForExistence(timeout: 20), "Home never loaded (mock feed missing?)")
        sleep(2)   // let initial focus settle
    }

    /// The user's exact repro: land on Home, move down into the shelves,
    /// move right a few cards (so we're NOT directly above the leading edge),
    /// then swipe up repeatedly. Focus must reach the tab bar.
    func test_up_from_mid_shelf_card_reaches_tab_bar() {
        let app = launchHome()
        waitForHome(app)

        // Down into the first shelf (Continue Watching), then right two cards.
        press(.down, times: 2)
        press(.right, times: 2)

        // Now try to come back up: shelf → featured hero → tab bar.
        // Generous press budget; the assertion is what matters.
        let homeTab = app.buttons["Home"].firstMatch
        var reachedTabBar = false
        for _ in 0..<8 {
            press(.up)
            if homeTab.exists && homeTab.hasFocus {
                reachedTabBar = true
                break
            }
        }

        XCTAssertTrue(
            reachedTabBar,
            """
            Focus never reached the tab bar. Focused element after presses: \
            \(app.descendants(matching: .any).matching(NSPredicate(format: "hasFocus == true")).firstMatch.debugDescription)
            """
        )
    }

    /// Sanity check the stepping stone: up from a card in the first shelf must
    /// land on the full-width featured hero, which then yields to the tab bar.
    func test_up_from_first_shelf_lands_on_featured_hero() {
        let app = launchHome()
        waitForHome(app)

        press(.down, times: 2)
        press(.right, times: 3)
        press(.up)

        let heroFocused = app.buttons
            .matching(identifier: "featured-slide")
            .matching(NSPredicate(format: "hasFocus == true"))
            .firstMatch
        XCTAssertTrue(heroFocused.exists, "Up from a shelf card should land on the featured hero")
    }
}

/// The creator page had the same trap: a tall non-focusable hero above the
/// posts grid meant "up" from the grid dead-ended at the Posts header and the
/// hero could never be scrolled back into view. The hero is now a focusable
/// (inert) anchor, so up from the grid must reach it.
final class CreatorFocusUITests: XCTestCase {

    override func setUp() {
        continueAfterFailure = false
    }

    private func press(_ button: XCUIRemote.Button, times: Int = 1) {
        for _ in 0..<times {
            XCUIRemote.shared.press(button)
            usleep(400_000)
        }
    }

    func test_up_from_posts_grid_reaches_hero() {
        let app = XCUIApplication()
        app.launchEnvironment["GALLERY_SCREEN"] = "creator"
        app.launchEnvironment["GALLERY_MOCK"] = "1"
        app.launch()

        let hero = app.buttons.matching(identifier: "creator-hero").firstMatch
        XCTAssertTrue(hero.waitForExistence(timeout: 20), "Creator page never loaded")
        sleep(2)

        // Down into the posts grid and across a column, then come back up.
        press(.down, times: 2)
        press(.right, times: 1)

        var reachedHero = false
        for _ in 0..<8 {
            press(.up)
            if hero.hasFocus {
                reachedHero = true
                break
            }
        }

        XCTAssertTrue(
            reachedHero,
            """
            Up from the posts grid never reached the creator hero. Focused: \
            \(app.descendants(matching: .any).matching(NSPredicate(format: "hasFocus == true")).firstMatch.debugDescription)
            """
        )
    }
}
