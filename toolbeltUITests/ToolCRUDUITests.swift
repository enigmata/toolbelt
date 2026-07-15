import XCTest

final class ToolCRUDUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    private func launchApp() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments += ["-uiTesting"]
        app.launch()
        return app
    }

    /// Fills the add form's identity fields; the list shows "brand model".
    private func addTool(in app: XCUIApplication, brand: String, model: String) {
        app.buttons["Add Tool"].firstMatch.tap()
        let brandField = app.textFields["Brand"]
        XCTAssertTrue(brandField.waitForExistence(timeout: 5))
        brandField.tap()
        brandField.typeText(brand)
        let modelField = app.textFields["Model Name"]
        modelField.tap()
        modelField.typeText(model)
        app.buttons["Save"].tap()
    }

    @MainActor
    func testAddAndSearchTool() throws {
        let app = launchApp()

        // Add
        addTool(in: app, brand: "Test", model: "Impact Driver")

        let cell = app.staticTexts["Test Impact Driver"]
        XCTAssertTrue(cell.waitForExistence(timeout: 5))

        // Search
        let searchField = app.searchFields.firstMatch
        XCTAssertTrue(searchField.waitForExistence(timeout: 5))
        searchField.tap()
        searchField.typeText("impact")
        XCTAssertTrue(cell.exists)
        searchField.typeText(" nonexistent")
        XCTAssertFalse(cell.exists)
    }

    @MainActor
    func testDeleteToolRequiresConfirmation() throws {
        let app = launchApp()

        addTool(in: app, brand: "Doomed", model: "Grinder")

        let cell = app.staticTexts["Doomed Grinder"]
        XCTAssertTrue(cell.waitForExistence(timeout: 5))

        // Delete via context menu, confirming the dialog
        cell.press(forDuration: 1.5)
        let deleteButton = app.buttons["Delete"]
        XCTAssertTrue(deleteButton.waitForExistence(timeout: 5))
        deleteButton.tap()
        let confirmDelete = app.buttons["Delete"].firstMatch
        XCTAssertTrue(confirmDelete.waitForExistence(timeout: 5))
        confirmDelete.tap()
        XCTAssertFalse(cell.waitForExistence(timeout: 3))
    }

    @MainActor
    func testDispositionChangeViaContextMenu() throws {
        let app = launchApp()

        addTool(in: app, brand: "Retiring", model: "Sander")

        let cell = app.staticTexts["Retiring Sander"]
        XCTAssertTrue(cell.waitForExistence(timeout: 5))

        cell.press(forDuration: 1.5)
        let markRetired = app.buttons["Mark Retired"]
        XCTAssertTrue(markRetired.waitForExistence(timeout: 5))
        markRetired.tap()

        // Retired tools leave the in-use list.
        XCTAssertFalse(cell.waitForExistence(timeout: 3))
    }
}
