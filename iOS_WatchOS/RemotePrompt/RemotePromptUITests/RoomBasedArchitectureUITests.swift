//
//  RoomBasedArchitectureUITests.swift
//  RemotePromptUITests
//
//  Phase 2.6 UI Tests for Room-Based Architecture
//

import XCTest

final class RoomBasedArchitectureUITests: XCTestCase {

    var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments += ["-UITestMode"]
        app.launch()
    }

    // MARK: - Phase 2.6.1: UI Tests

    func testRoomsListViewAppears() throws {
        let list = app.tables["rooms.list"]
        XCTAssertTrue(list.waitForExistence(timeout: 5))
        XCTAssertTrue(app.navigationBars["Rooms"].exists)
        XCTAssertTrue(list.cells.element(boundBy: 0).exists)
    }

    func testCreateRoomButtonExists() throws {
        let addButton = app.buttons["rooms.add"]
        XCTAssertTrue(addButton.exists)
        XCTAssertTrue(addButton.isEnabled)
    }

    func testCreateRoomFlow() throws {
        app.buttons["rooms.add"].tap()

        let nameField = app.textFields["createRoom.name"]
        XCTAssertTrue(nameField.waitForExistence(timeout: 2))
        nameField.tap()
        nameField.typeText("UITest Room")

        let pathField = app.textFields["createRoom.workspacePath"]
        pathField.tap()
        pathField.typeText("/Users/uitest/project")

        let iconField = app.textFields["createRoom.icon"]
        iconField.tap()
        iconField.typeText("🧪")

        app.buttons["createRoom.submit"].tap()

        let newRoomLabel = app.staticTexts["UITest Room"]
        XCTAssertTrue(newRoomLabel.waitForExistence(timeout: 2))
    }

    func testRoomDetailTabs() throws {
        app.tables["rooms.list"].cells.element(boundBy: 0).tap()
        let claudeTab = app.buttons["Claude"]
        XCTAssertTrue(claudeTab.waitForExistence(timeout: 2))
        let codexTab = app.buttons["Codex"]
        XCTAssertTrue(codexTab.exists)
        codexTab.tap()
        XCTAssertTrue(codexTab.isSelected)
    }

    // MARK: - Phase 2.6.3: Consistency UI Tests

    func testMessageSendingWithRoomContext() throws {
        app.tables["rooms.list"].cells.element(boundBy: 0).tap()

        let input = app.textFields["chat.input"]
        XCTAssertTrue(input.waitForExistence(timeout: 2))
        input.tap()
        input.typeText("UITest message")

        let sendButton = app.buttons["chat.send"]
        XCTAssertTrue(sendButton.isEnabled)
        sendButton.tap()

        let sentMessage = app.staticTexts["UITest message"]
        XCTAssertTrue(sentMessage.waitForExistence(timeout: 3))
        let assistantMessage = app.staticTexts["Preview response for UITest message"]
        XCTAssertTrue(assistantMessage.waitForExistence(timeout: 3))
    }
}
