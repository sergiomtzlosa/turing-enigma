import XCTest

final class TuringEnigmaUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    func testLaunchDemoAndEncipher() throws {
        let app = XCUIApplication()
        app.launchArguments += ["--ui-testing"]
        app.launch()

        XCTAssertTrue(
            app.staticTexts["app.title"].waitForExistence(timeout: 20),
            "The main window did not appear"
        )
        XCTAssertTrue(app.buttons["mode.enigma"].exists)
        XCTAssertTrue(app.buttons["mode.bombe"].exists)
        XCTAssertTrue(app.buttons["camera.center"].exists)

        let demo = app.buttons["demo.button"]
        XCTAssertTrue(demo.waitForExistence(timeout: 5))
        demo.click()

        let windows = app.staticTexts["windows.text"]
        XCTAssertTrue(windows.waitForExistence(timeout: 5))
        XCTAssertEqual(windows.label, "EHL")

        let encipher = app.buttons["encipher.button"]
        XCTAssertTrue(encipher.isEnabled)
        encipher.click()

        let output = app.staticTexts["output.text"]
        let recovered = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "label CONTAINS %@", "GQGYW"),
            object: output
        )
        XCTAssertEqual(
            XCTWaiter().wait(for: [recovered], timeout: 15),
            .completed,
            "Expected the demo ciphertext in the output field, got \(output.label)"
        )

        app.buttons["bombe.send"].click()
        XCTAssertTrue(app.buttons["bombe.run"].waitForExistence(timeout: 5))
    }
}
