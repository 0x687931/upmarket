//
//  UpmarketUITests.swift
//  UpmarketUITests
//
//  Created by Andrew McArdle on 30/5/2026.
//

import XCTest

final class UpmarketUITests: XCTestCase {

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    func testPrimaryConversionWindowIsMounted() throws {
        let app = XCUIApplication()
        app.launch()

        let primaryView = app.descendants(matching: .any)["PrimaryConversionView"]
        XCTAssertTrue(primaryView.waitForExistence(timeout: 3))
        XCTAssertTrue(app.buttons["ChooseDocumentButton"].exists)
    }

    @MainActor
    func testLaunchPerformance() throws {
        // This measures how long it takes to launch your application.
        measure(metrics: [XCTApplicationLaunchMetric()]) {
            XCUIApplication().launch()
        }
    }
}
