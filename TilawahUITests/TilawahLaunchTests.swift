//
//  TilawahLaunchTests.swift
//  TilawahUITests
//
//  Release-readiness smoke tests (Phase 7): the app launches to the tab bar
//  and the local-first tabs render without network. Assertions use only
//  on-device state (tabs, empty-library copy) — never provider data — so
//  they pass offline as well as in CI.
//

import XCTest

final class TilawahLaunchTests: XCTestCase {
    private var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        // Clean slate every launch (in-memory stack; see TilawahApp).
        // Makes the empty-state assertions deterministic on reused sims.
        app.launchArguments = ["-TilawahResetData"]
        app.launch()
    }

    func testLaunchShowsTabBar() throws {
        let tabs = app.tabBars.firstMatch
        XCTAssertTrue(tabs.waitForExistence(timeout: 10), "Tab bar must appear on launch.")
        for label in ["تصفح", "المكتبة", "التنزيلات"] {
            XCTAssertTrue(
                tabs.buttons[label].exists,
                "Tab \(label) must exist."
            )
        }
        add(XCTAttachment(screenshot: app.screenshot()))
    }

    func testLibraryTabShowsLocalEmptyState() throws {
        let tabs = app.tabBars.firstMatch
        XCTAssertTrue(tabs.waitForExistence(timeout: 10))
        tabs.buttons["المكتبة"].tap()
        // Empty-library copy is local SwiftData state — no network needed.
        XCTAssertTrue(
            app.staticTexts["لا توجد مفضلة بعد. اضغط مطولًا على أي سورة لإضافتها."]
                .waitForExistence(timeout: 10),
            "Library must render its empty state on a fresh install."
        )
    }

    func testDownloadsTabShowsEmptyState() throws {
        let tabs = app.tabBars.firstMatch
        XCTAssertTrue(tabs.waitForExistence(timeout: 10))
        tabs.buttons["التنزيلات"].tap()
        XCTAssertTrue(
            app.staticTexts["لا توجد تنزيلات"].waitForExistence(timeout: 10),
            "Downloads must render its empty state on a fresh install."
        )
    }
}
