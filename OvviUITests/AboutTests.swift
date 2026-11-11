import UniformTypeIdentifiers
import XCTest

extension OvviUITests {
    func testAboutWindowOpensTheAcknowledgements() throws {
        XCTAssertTrue(element("workspace.w1").exists(within: connect))
        app.menuBarItems["Ovvi"].menuItems["About Ovvi"].click()
        let about = app.windows.matching(NSPredicate(format: "identifier BEGINSWITH 'about'")).firstMatch
        XCTAssertTrue(about.exists(within: 3))
        keepScreenshot("about", of: about)
        XCTAssertTrue(about.staticTexts["Ovvi"].exists)
        XCTAssertTrue(about.staticTexts
            .matching(NSPredicate(format: "label BEGINSWITH 'Version ' OR value BEGINSWITH 'Version '")).firstMatch
            .exists)
        about.typeKey("w", modifierFlags: .command)
        XCTAssertTrue(about.vanishes(within: 2))
        app.menuBarItems["Ovvi"].menuItems["About Ovvi"].click()
        XCTAssertTrue(about.exists(within: 3))

        let textEdit = XCUIApplication(bundleIdentifier: "com.apple.TextEdit")
        let opener = NSWorkspace.shared.urlForApplication(toOpen: .plainText)
        guard opener?.lastPathComponent == "TextEdit.app", textEdit.state == .notRunning else {
            throw XCTSkip("TextEdit is open, or is not this Mac's .txt opener: the acknowledgements are not checked")
        }
        addTeardownBlock { textEdit.terminate() }
        element("about.acknowledgements", in: about).click()
        let texts = textEdit.windows.matching(NSPredicate(format: "title BEGINSWITH 'Acknowledgements'")).firstMatch
        XCTAssertTrue(texts.exists(within: 10))
    }
}
