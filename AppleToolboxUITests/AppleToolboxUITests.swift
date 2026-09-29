//
//  AppleToolboxUITests.swift
//  AppleToolboxUITests
//
//  Created by Joris Conrad on 25.08.26.
//

import XCTest

final class AppleToolboxUITests: XCTestCase {

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    func testSidebarListsCategoriesAndTheEntitlementExplorer() throws {
        let app = XCUIApplication()
        app.launch()
        XCTAssertTrue(app.buttons["category.Security"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.buttons["category.Location"].exists)
        XCTAssertTrue(app.buttons["inspect.entitlements"].exists)
    }

    @MainActor
    func testCryptoKitHashesWithTheRealAPI() throws {
        let app = XCUIApplication()
        app.launch()
        app.buttons["category.Security"].tap()
        let experiment = app.buttons["experiment.cryptokit"]
        XCTAssertTrue(experiment.waitForExistence(timeout: 10))
        experiment.tap()

        let hash = app.buttons["Run Hash"]
        scroll(app, until: hash)
        hash.tap()
        let digest = app.staticTexts.containing(NSPredicate(format: "label CONTAINS %@", "Digest (32 bytes):")).firstMatch
        XCTAssertTrue(digest.waitForExistence(timeout: 5))
    }

    @MainActor
    func testLaunchPerformance() throws {
        measure(metrics: [XCTApplicationLaunchMetric()]) {
            XCUIApplication().launch()
        }
    }

    /// The detail list is lazy: rows further down only exist once they are scrolled into view.
    @MainActor
    private func scroll(_ app: XCUIApplication, until element: XCUIElement, attempts: Int = 6) {
        for _ in 0..<attempts where !element.isHittable {
            app.swipeUp()
        }
        XCTAssertTrue(element.waitForExistence(timeout: 5))
    }
}
