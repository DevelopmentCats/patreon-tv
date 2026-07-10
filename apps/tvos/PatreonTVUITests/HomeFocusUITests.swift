//
//  HomeFocusUITests.swift
//  PatreonTVUITests
//
//  Reproduces the reported Home focus trap with real Siri Remote presses:
//  from a card in the first shelf, swiping up must eventually reach the top
//  tab bar (via the hero's Play button). Runs fully offline against
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

    /// The user's exact repro: land on Home, move down into the shelves,
    /// move right a few cards (so we're NOT directly above the Play pill),
    /// then swipe up repeatedly. Focus must reach the tab bar.
    func test_up_from_mid_shelf_card_reaches_tab_bar() {
        let app = launchHome()

        // Home is loaded when the hero's Play button exists.
        let play = app.buttons["Play"].firstMatch
        XCTAssertTrue(play.waitForExistence(timeout: 20), "Home never loaded (mock feed missing?)")
        // Let initial focus settle.
        sleep(2)

        // Down into the first shelf (Continue Watching), then right two cards.
        press(.down, times: 2)
        press(.right, times: 2)

        // Now try to come back up: shelf → hero section → tab bar.
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

    /// Sanity check the fix's stepping stone: up from the FIRST card of the
    /// first shelf must land on the hero's Play button (full-width
    /// focusSection catches the swipe even though the pill sits at the
    /// leading edge).
    func test_up_from_first_shelf_lands_on_play_button() {
        let app = launchHome()

        let play = app.buttons["Play"].firstMatch
        XCTAssertTrue(play.waitForExistence(timeout: 20))
        sleep(2)

        press(.down, times: 2)
        press(.right, times: 3)   // well past the pill's x-range
        press(.up)

        XCTAssertTrue(play.hasFocus, "Up from a mid-shelf card should land on the hero Play button")
    }
}
