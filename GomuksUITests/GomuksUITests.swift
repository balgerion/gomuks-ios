import XCTest

final class GomuksUITests: XCTestCase {
    private let server = ProcessInfo.processInfo.environment["TEST_GOMUKS_URL"] ?? "http://localhost:29325"

    override func setUp() {
        continueAfterFailure = false
    }

    func testLoginRoomAndKeyboard() throws {
        let app = XCUIApplication()
        app.launch()

        let connect = app.buttons["Connect"]
        wait(connect, 30, app)
        let serverField = app.textFields.element(boundBy: 0)
        serverField.coordinate(withNormalizedOffset: CGVector(dx: 0.98, dy: 0.5)).tap()
        serverField.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: 60) + server)
        let username = app.textFields.element(boundBy: 1)
        username.tap()
        username.typeText("admin")
        let password = app.secureTextFields.element(boundBy: 0)
        password.tap()
        password.typeText("adminpass")
        attach(app, "setup")
        let connected = Date()
        connect.tap()

        let mainRoom = app.webViews.staticTexts["Main Room"]
        wait(mainRoom, 45, app)
        print("PERF connect_to_room_list_s=\(Date().timeIntervalSince(connected))")
        attach(app, "room-list")

        let settings = app.webViews.buttons["Server and account"]
        wait(settings, 10, app)
        settings.tap()
        wait(connect, 10, app)
        attach(app, "settings")
        app.buttons["Cancel"].tap()
        wait(mainRoom, 10, app)

        let opened = Date()
        mainRoom.tap()
        let newest = app.webViews.staticTexts.containing(NSPredicate(format: "label BEGINSWITH '#149'")).firstMatch
        wait(newest, 30, app)
        print("PERF open_room_s=\(Date().timeIntervalSince(opened))")
        attach(app, "room")

        let showMedia = app.webViews.staticTexts["Show media"]
        wait(showMedia, 10, app)
        showMedia.tap()
        let thumbnail = app.webViews.images["test.png"]
        wait(thumbnail, 10, app)
        thumbnail.tap()
        wait(app.buttons["gomuks-image-viewer-close"], 10, app)
        wait(app.images["gomuks-image-viewer-image"], 15, app)
        attach(app, "image-viewer")
        app.buttons["gomuks-image-viewer-close"].tap()
        XCTAssertTrue(app.buttons["gomuks-image-viewer-close"].waitForNonExistence(timeout: 5))
        wait(newest, 10, app)

        let composer = app.webViews.textViews.firstMatch
        wait(composer, 10, app)
        composer.tap()
        let keyboard = app.keyboards.firstMatch
        wait(keyboard, 10, app)
        sleep(2)
        attach(app, "keyboard")

        let assistant = app.otherElements["SystemInputAssistantView"]
        let keyboardTop = assistant.exists ? min(assistant.frame.minY, keyboard.frame.minY) : keyboard.frame.minY
        let webView = app.webViews.firstMatch
        print("GEOMETRY newest=\(newest.frame) composer=\(composer.frame) webview=\(webView.frame) keyboardTop=\(keyboardTop)")
        XCTAssertEqual(webView.frame.maxY, keyboardTop, accuracy: 1, "web view does not end at keyboard")
        XCTAssertFalse(app.buttons["Done"].exists, "input accessory bar is visible")
        XCTAssertLessThanOrEqual(composer.frame.maxY, keyboardTop + 1, "composer hidden by keyboard")
        XCTAssertLessThan(keyboardTop - composer.frame.maxY, 40, "gap between composer and keyboard")
        XCTAssertLessThanOrEqual(newest.frame.maxY, composer.frame.minY + 1, "newest message hidden behind composer")
        XCTAssertTrue(newest.isHittable, "newest message not visible")
    }

    private func wait(_ element: XCUIElement, _ timeout: TimeInterval, _ app: XCUIApplication,
                      file: StaticString = #filePath, line: UInt = #line) {
        if element.waitForExistence(timeout: timeout) {
            return
        }
        attach(app, "failure")
        print("TREE-BEGIN\n\(app.debugDescription)\nTREE-END")
        XCTFail("not found: \(element)", file: file, line: line)
    }

    private func attach(_ app: XCUIApplication, _ name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
