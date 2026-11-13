import AppKit
import HerdrKit
import WebKit

extension Browser: WKNavigationDelegate {
    /// Not at `didFinish`: an image, a font or a fetch that never answers would keep the loader over a drawn page.
    /// Weak: a hidden page draws no frame, and a dropped card must not wait for one.
    func webView(_ webView: WKWebView, didCommit _: WKNavigation!) {
        failure = nil
        loaded = true
        showAddress()
        webView.callAsyncJavaScript(Self.drawnScript, in: nil, in: .defaultClient) { [weak self, weak webView] _ in
            // Not from a view a network switch replaced.
            if let self, webView === view {
                ready = true
            }
        }
    }

    /// Parsed, then a frame painted (a task after the frame's callback).
    private static let drawnScript = """
    if (document.readyState === 'loading') await new Promise(r => addEventListener('DOMContentLoaded', r))
    await new Promise(r => requestAnimationFrame(() => setTimeout(r)))
    """

    func webView(_: WKWebView, didFinish _: WKNavigation!) {
        ready = true
        reloaded = false
        save()
        loadIcon()
    }

    func webView(_: WKWebView, didFail _: WKNavigation!, withError error: any Error) {
        failed(error)
    }

    func webView(_: WKWebView, didFailProvisionalNavigation _: WKNavigation!, withError error: any Error) {
        failed(error)
    }

    private func failed(_ error: any Error) {
        ready = true
        let error = error as NSError
        // A load replaced by another, or a download.
        guard error.code != NSURLErrorCancelled,
              error.domain != "WebKitErrorDomain" || error.code != 102 else { return }
        let url = (error.userInfo[NSURLErrorFailingURLErrorKey] as? URL).map { Self.shown($0, alias) }
            ?? URL(string: address)
        failure = failureText(error, url)
        if let url {
            address = url.absoluteString
        }
    }

    /// The system ends a page's process under memory pressure or after a long sleep.
    func webViewWebContentProcessDidTerminate(_: WKWebView) {
        guard !reloaded else {
            ready = true
            failure = ("The page stopped working", nil)
            return
        }
        reloaded = true
        reload()
    }

    /// WebKit downloads a ⌥-clicked link.
    func webView(_: WKWebView, decidePolicyFor action: WKNavigationAction) async -> WKNavigationActionPolicy {
        let flags = action.modifierFlags
        if action.navigationType == .linkActivated, !flags.isDisjoint(with: [.command, .option]),
           let url = action.request.url, openTab(url, side: !flags.contains(.command))
        {
            return .cancel
        }
        // Sent as it is: an OAuth `form_post` keeps its body.
        if alias != nil, action.targetFrame?.isMainFrame == true, let url = action.request.url,
           Self.loopback.contains(url.host?.lowercased() ?? "")
        {
            var request = action.request
            request.url = Self.web(url, alias)
            proxied { self.view.load(request) }
            return .cancel
        }
        // A remote card never shows This Mac's files (a history entry or a script may ask for one).
        if store?.machine.isRemote != false, action.request.url?.isFileURL == true {
            return .cancel
        }
        guard let url = action.request.url,
              !["http", "https", "file", "about", "blob", "data"].contains(url.scheme?.lowercased() ?? "")
        else { return .allow }
        if action.navigationType == .linkActivated, action.targetFrame?.isMainFrame != false {
            NSWorkspace.shared.open(url)
        }
        return .cancel
    }
}

extension Browser: WKUIDelegate {
    /// An OAuth popup needs its opener, and WebKit does not say whether a `target=_blank` link has `rel=opener`.
    func webView(_ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration,
                 for action: WKNavigationAction, windowFeatures _: WKWindowFeatures) -> WKWebView?
    {
        let source = webView as? BrowserView
        let how = source?.opens ?? (action.navigationType == .linkActivated ? .tab : nil)
        source?.opens = nil
        if let how, let url = action.request.url, openTab(url, side: how == .side) {
            return nil
        }
        guard action.navigationType == .other, how == nil else {
            webView.load(action.request)
            return nil
        }
        let popup = BrowserView(frame: .zero, configuration: configuration)
        popup.uiDelegate = self
        popup.onKey = { [weak self] in self?.key($0) ?? false }
        popup.onKeyboard = view.onKeyboard
        popup.setAccessibilityIdentifier("browser.\(paneID).popup")
        popup.takeKeyboard()
        self.popup = (popup, action.request.url?.host ?? "")
        return popup
    }

    func webViewDidClose(_ webView: WKWebView) {
        if webView === popup?.view {
            closePopup()
        }
    }

    func webView(_ webView: WKWebView, runJavaScriptAlertPanelWithMessage message: String,
                 initiatedByFrame frame: WKFrameInfo) async
    {
        _ = await dialog(webView, message, frame, buttons: ["OK"])
    }

    func webView(_ webView: WKWebView, runJavaScriptConfirmPanelWithMessage message: String,
                 initiatedByFrame frame: WKFrameInfo) async -> Bool
    {
        await dialog(webView, message, frame, buttons: ["OK", "Cancel"]) == .alertFirstButtonReturn
    }

    func webView(_ webView: WKWebView, runOpenPanelWith parameters: WKOpenPanelParameters,
                 initiatedByFrame _: WKFrameInfo) async -> [URL]?
    {
        guard let window = webView.window else { return nil }
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = parameters.allowsMultipleSelection
        panel.canChooseDirectories = parameters.allowsDirectories
        return await panel.beginSheetModal(for: window) == .OK ? panel.urls : nil
    }

    private func dialog(_ webView: WKWebView, _ message: String, _ frame: WKFrameInfo,
                        buttons: [String]) async -> NSApplication.ModalResponse
    {
        guard let window = webView.window else { return .cancel }
        let alert = NSAlert()
        let origin = frame.securityOrigin, port = origin.port > 0 ? ":\(origin.port)" : ""
        alert.messageText = (origin.host.isEmpty ? origin.protocol : origin.host) + port
        alert.informativeText = message
        buttons.forEach { alert.addButton(withTitle: $0) }
        return await alert.beginSheetModal(for: window)
    }
}

extension Browser {
    func closePopup() {
        let had = popup.map { $0.view.window?.firstResponder === $0.view } ?? false
        popup = nil
        if had {
            view.takeKeyboard()
        }
    }

    /// The user picked the link, so its origin is approved.
    func openTab(_ link: URL, side: Bool) -> Bool {
        // Not `mailto:`: `url` reads an address without `://` as a host.
        guard ["http", "https", "file"].contains(link.scheme?.lowercased() ?? ""), let store,
              let pane = store.pane(paneID), let workspace = store.workspace(of: pane.tabID),
              let url = url(Self.shown(link, alias).absoluteString)
        else { return false }
        approve(url)
        let label = store.newLabel(Registry.browser, arg: url.absoluteString)
        if store.machine.isRemote {
            Self.keep(viaMac, label, store)
        }
        // From a floating card, in a floating window of its own.
        let floating = WindowPages.windows.lazy.flatMap(\.withFloats)
            .first { page in page.store === store && pane.terminalID.map { page.floating[$0] != nil } == true }
        Task {
            var made: HerdrKit.Pane?
            await store.write {
                made = try await store.newPane($0, in: workspace.id, cwd: pane.cwd ?? "~", label: label,
                                               side && floating == nil ? .split(tab: pane.tabID, pane: pane.id, .right)
                                                   : .tab(after: pane.tabID))
            }
            if let floating, let made {
                await floating.floatNew(made)
            }
        }
        return true
    }

    /// WebKit has no favicon API: the page fetches its icon, so its proxy, its rules and CORS apply as to any fetch.
    func loadIcon() {
        let page = view.url
        Task {
            let found = try? await view.callAsyncJavaScript(Self.iconScript, arguments: ["known": icon?.href ?? ""],
                                                            contentWorld: .defaultClient) as? [Any]
            // Not over a newer page's.
            guard view.url == page, let href = found?.first as? String, href != icon?.href else { return }
            icon = (href, (found?.last as? String).flatMap { Data(base64Encoded: $0) }.flatMap(NSImage.init(data:)))
            iconPNG = icon?.image.flatMap(ClosedPages.png)
            save()
        }
    }

    private static let iconScript = """
    const link = document.querySelector('link[rel~=icon]')
    const href = link ? link.href : new URL('/favicon.ico', location.href).href
    if (href === known) return [href, null]
    try {
      const response = await fetch(href, { signal: AbortSignal.timeout(5000) })
      const blob = await response.blob()
      if (!response.ok || blob.size > 1048576) return [href, null]
      let text = ''
      for (const byte of new Uint8Array(await blob.arrayBuffer())) text += String.fromCharCode(byte)
      return [href, btoa(text)]
    } catch { return [href, null] }
    """
}
