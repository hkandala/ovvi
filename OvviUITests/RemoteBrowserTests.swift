import XCTest

/// On CI Key Host is this Mac over SSH (`scripts/ci-sshd.sh`), so one port serves both machines.
extension OvviUITests {
    /// Its script goes as base64: the runner is sandboxed, and a shell of the session writes it.
    func serveWho(_ port: Int, from pane: String) async throws {
        let script = """
        import http.server, socketserver, subprocess, sys
        class Who(http.server.BaseHTTPRequestHandler):
            def do_GET(self):
                end = "127.0.0.1:%d->" % self.client_address[1]
                out = subprocess.run(["lsof", "+c", "0", "-nP", "-iTCP@" + end[:-2], "-Fcn"],
                                     capture_output=True, text=True).stdout.split("\\n")
                who = command = ""
                for line in out:
                    if line.startswith("c"):
                        command = line[1:]
                    elif line.startswith("n" + end):
                        who = command
                body = ("via=%s host=%s" % (who, self.headers["Host"])).encode()
                self.send_response(200)
                self.send_header("Content-Type", "text/plain; charset=utf-8")
                self.send_header("Content-Length", str(len(body)))
                self.end_headers()
                self.wfile.write(body)
        # Threads: WebKit keeps a spare connection open, which held a one-thread server's next page for 30 s. Not
        # HTTPServer: its getfqdn() lookup raised the Local Network prompt on CI, over the next tests' windows.
        server = socketserver.ThreadingTCPServer(("127.0.0.1", int(sys.argv[1])), Who)
        print("ovvi-who-ready", flush=True)
        server.serve_forever()
        """
        let file = "/tmp/ovvi-e2e-who.py", encoded = Data(script.utf8).base64EncodedString()
        try await send("echo \(encoded) | base64 -d >\(file) && clear && python3 \(file) \(port)\r", to: pane)
        // The first python3 on CI starts slowly (xcrun).
        try await waitFor(pane, times: 300) { $0.contains("ovvi-who-ready") }
    }

    func whoText(_ prefix: String, in window: XCUIElement) -> XCUIElement {
        window.webViews.staticTexts.matching(NSPredicate(format: "value BEGINSWITH %@", prefix)).firstMatch
    }

    func testARemoteBrowserCardLoadsItsMachinesLocalhost() async throws {
        try await skipWithoutSSH()
        relaunch(one, ["-machines", Self.keyHost])
        XCTAssertTrue(element("workspace.w2").exists(within: connect))
        let identifier = app.windows.firstMatch.identifier
        let first = app.windows[identifier]
        let (tab, left) = try await createWorkspace("remote localhost")
        let workspace = workspace(of: tab)
        element("workspace.\(workspace)").click()
        try await waitForPrompt(left)
        let port = Int.random(in: 47100 ... 47900)
        try await serveWho(port, from: left)
        let browser = try await split(left)
        try await Self.call(
            one,
            "pane.rename",
            ["pane_id": browser, "label": "ovvi:browser#e2erem http://localhost:\(port)/"],
        )
        XCTAssertTrue(whoText("via=com.apple.WebKit", in: first).exists(within: 10))
        XCTAssertFalse(element("browser.\(browser).machine", in: first).exists)

        element("titlebar.machine", in: first).click()
        app.menuItems["Key Host"].firstMatch.click()
        let remote = try otherWindow(than: identifier)
        element("workspace.\(workspace)", in: remote).click()
        element("tab.\(tab)", in: remote).click()
        let page = whoText("via=sshd", in: remote)
        XCTAssertTrue(page.exists(within: connect))
        XCTAssertTrue((page.value as? String ?? "").hasSuffix("host=key-host.localhost:\(port)"), "\(page.value ?? "")")
        XCTAssertEqual(element("browser.\(browser).address", in: remote).value as? String, "http://localhost:\(port)/")
        let chip = element("browser.\(browser).machine", in: remote)
        XCTAssertEqual(chip.label, "Key Host")
        keepScreenshot("remote browser card", of: remote)

        chip.click()
        let mac = whoText("via=com.apple.WebKit", in: remote)
        XCTAssertTrue(mac.exists(within: 10))
        XCTAssertTrue((mac.value as? String ?? "").hasSuffix("host=localhost:\(port)"), "\(mac.value ?? "")")
        XCTAssertEqual(chip.label, "This Mac")
        keepScreenshot("remote browser card on This Mac's network", of: remote)
        chip.click()
        XCTAssertTrue(whoText("via=sshd", in: remote).exists(within: connect))
        XCTAssertEqual(chip.label, "Key Host")

        // A port nothing listens on: the proxy's refusal at once (ssh's own close makes WebKit wait 60 s).
        element("browser.\(browser).address", in: remote).click()
        app.typeText("localhost:\(port + 1)\r")
        let message = element("browser.\(browser).message", in: remote)
        XCTAssertTrue(until(5) { message.value as? String == "Nothing answers on localhost:\(port + 1) on Key Host" },
                      "\(message.value ?? "")")
        let address = element("browser.\(browser).address", in: remote).value as? String ?? ""
        XCTAssertTrue(address.hasPrefix("http://localhost:\(port + 1)"), address)
        try await asksOverTheFailure(browser, port, in: remote)

        try await reloadsAfterTheForwardEnds(browser, port, in: remote)
    }

    /// A page from elsewhere asks over the failure, an approved one ends the question, and Not Now shows the
    /// machine's own name.
    private func asksOverTheFailure(_ browser: String, _ port: Int, in remote: XCUIElement) async throws {
        try await expect("the label follows") { try await paneLabel(browser).contains("localhost:\(port + 1)") }
        try await relabel(browser, "ovvi:browser#e2erem https://ovvi.invalid/")
        let open = element("browser.\(browser).open", in: remote)
        XCTAssertTrue(open.exists(within: 5), shown(browser, remote))
        try await relabel(browser, "ovvi:browser#e2erem http://localhost:\(port)/")
        XCTAssertTrue(open.vanishes(within: 5))
        XCTAssertTrue(whoText("via=sshd", in: remote).exists(within: connect))
        try await relabel(browser, "ovvi:browser#e2erem https://ovvi.invalid/two")
        XCTAssertTrue(open.exists(within: 5))
        element("browser.\(browser).not-now", in: remote).click()
        XCTAssertTrue(open.vanishes(within: 3))
        XCTAssertEqual(element("browser.\(browser).address", in: remote).value as? String, "http://localhost:\(port)/")
    }

    /// Each time a new name: WebKit keeps a spare connection to the last one.
    private func reloadsAfterTheForwardEnds(_ browser: String, _ port: Int, in remote: XCUIElement) async throws {
        let ports = try await Self.post("\(one)/ssh-unforward", Data("ovvi-key".utf8))
        XCTAssertFalse(ports.isEmpty)
        open("healed.localhost:\(port)", in: browser, remote)
        XCTAssertTrue(
            page(from: "healed.localhost:\(port)", in: remote).exists(within: connect),
            shown(browser, remote),
        )
        let pids = try await Self.post("\(one)/ssh-drop", Data("ovvi-key".utf8))
        XCTAssertFalse(pids.isEmpty)
        open("dropped.localhost:\(port)", in: browser, remote)
        XCTAssertTrue(
            page(from: "dropped.localhost:\(port)", in: remote).exists(within: connect),
            shown(browser, remote),
        )
        addTeardownBlock { [one] in _ = try? await Self.post("\(one)/ssh-drop", Data("ovvi-key".utf8)) }
        let stopped = try await Self.post("\(one)/ssh-stop", Data("ovvi-key".utf8))
        XCTAssertFalse(stopped.isEmpty)
        open("stopped.localhost:\(port)", in: browser, remote)
        XCTAssertTrue(
            page(from: "stopped.localhost:\(port)", in: remote).exists(within: connect),
            shown(browser, remote),
        )
    }

    /// The who page through the machine for `host` (sshd's process may be `sshd-session`).
    private func page(from host: String, in window: XCUIElement) -> XCUIElement {
        let format = "value BEGINSWITH 'via=sshd' AND value ENDSWITH %@"
        return window.webViews.staticTexts.matching(NSPredicate(format: format, "host=\(host)")).firstMatch
    }

    private func shown(_ browser: String, _ window: XCUIElement) -> String {
        let message = element("browser.\(browser).message", in: window)
        return message.exists ? "\(message.value ?? "")" : "no failure shown"
    }

    /// Clicked until it has the keyboard: right after a dropped master the page shows Reconnecting for a moment, and
    /// takes no clicks (on CI).
    private func open(_ address: String, in browser: String, _ window: XCUIElement) {
        let field = element("browser.\(browser).address", in: window)
        XCTAssertTrue(until(connect) {
            field.click()
            return hasKeyboard(field)
        }, "the keyboard is on \(keyboardOwner())")
        app.typeKey("a", modifierFlags: .command)
        app.typeText("\(address)\r")
    }
}
