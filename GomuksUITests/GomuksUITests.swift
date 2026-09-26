import XCTest

final class GomuksUITests: XCTestCase {
    private let server = ProcessInfo.processInfo.environment["TEST_GOMUKS_URL"] ?? "http://localhost:29325"

    override func setUp() {
        continueAfterFailure = false
    }

    func testLoginRoomAndKeyboard() throws {
        let app = XCUIApplication()
        let launched = Date()
        app.launch()

        let connect = app.buttons["Connect"]
        XCTAssertTrue(connect.waitForExistence(timeout: 30))
        let serverField = app.textFields.element(boundBy: 0)
        serverField.tap()
        serverField.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: 60) + server)
        let username = app.textFields.element(boundBy: 1)
        username.tap()
        username.typeText("admin")
        let password = app.secureTextFields.element(boundBy: 0)
        password.tap()
        password.typeText("adminpass")
        attach(app, "setup")
        connect.tap()

        let mainRoom = app.webViews.staticTexts["Main Room"]
        XCTAssertTrue(mainRoom.waitForExistence(timeout: 90))
        print("PERF launch_to_room_list_s=\(Date().timeIntervalSince(launched))")
        attach(app, "room-list")

        let settings = app.webViews.buttons["Server and account"]
        XCTAssertTrue(settings.waitForExistence(timeout: 10))
        settings.tap()
        XCTAssertTrue(connect.waitForExistence(timeout: 10))
        attach(app, "settings")
        app.buttons["Cancel"].tap()
        XCTAssertTrue(mainRoom.waitForExistence(timeout: 10))

        let opened = Date()
        mainRoom.tap()
        let newest = app.webViews.staticTexts.containing(NSPredicate(format: "label BEGINSWITH '#149'")).firstMatch
        XCTAssertTrue(newest.waitForExistence(timeout: 30))
        print("PERF open_room_s=\(Date().timeIntervalSince(opened))")
        attach(app, "room")

        let composer = app.webViews.textViews.firstMatch
        XCTAssertTrue(composer.waitForExistence(timeout: 10))
        composer.tap()
        let keyboard = app.keyboards.firstMatch
        XCTAssertTrue(keyboard.waitForExistence(timeout: 10))
        sleep(2)
        attach(app, "keyboard")

        let keyboardTop = keyboard.frame.minY
        print("GEOMETRY newest=\(newest.frame) composer=\(composer.frame) keyboard=\(keyboard.frame)")
        XCTAssertFalse(app.buttons["Done"].exists, "input accessory bar is visible")
        XCTAssertLessThanOrEqual(composer.frame.maxY, keyboardTop + 1, "composer hidden by keyboard")
        XCTAssertLessThan(keyboardTop - composer.frame.maxY, 40, "gap between composer and keyboard")
        XCTAssertLessThanOrEqual(newest.frame.maxY, composer.frame.minY + 1, "newest message hidden behind composer")
        XCTAssertTrue(newest.isHittable, "newest message not visible")
    }

    private func attach(_ app: XCUIApplication, _ name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
