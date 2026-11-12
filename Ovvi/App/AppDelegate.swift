import AppKit
import HerdrKit
import SwiftUI
import UserNotifications

/// The notification delegate goes in at launch, or a click that starts the app is lost.
final class AppDelegate: NSObject, NSApplicationDelegate, UNUserNotificationCenterDelegate {
    /// Set from macOS's decode of the restorable state until launch ends: a restored window's scene storage comes
    /// back a moment after it first shows.
    static var restoring = false
    /// macOS restores full screen windows ahead of the end of launch.
    static var restoredFullScreen: Set<ObjectIdentifier> = []

    func application(_: NSApplication, didDecodeRestorableState _: NSCoder) {
        Self.restoring = true
    }

    func applicationDidFinishLaunching(_: Notification) {
        Self.restoring = false
        // A first launch shows the welcome alone. A reset cannot reach the windows macOS saved (its folder needs Full
        // Disk Access): closed now, they are forgotten.
        if Welcome.firstLaunch {
            NSApp.windows.filter(\.canBecomeMain).forEach { $0.close() }
        }
        Self.restoredFullScreen = Set(NSApp.windows.filter { $0.styleMask.contains(.fullScreen) }
            .map(ObjectIdentifier.init))
        PluginBuilds.writeTypes()
        Task { await DefaultPlugins.shared.install() }
        // Usually after restored windows made their cards; if not, it costs one more page process.
        Task {
            try? await Task.sleep(for: .seconds(3))
            await Browser.prewarm()
        }
        // A quit with no window open saves none, so macOS opens none. SwiftUI's own first window may not be on
        // screen this early.
        DispatchQueue.main.async {
            if !NSApp.windows.contains(where: \.canBecomeMain), !Welcome.firstLaunch {
                WindowPages.openWindow?(id: WindowPages.mainScene)
            }
            Welcome.showOnFirstLaunch()
        }
    }

    func applicationShouldTerminate(_ app: NSApplication) -> NSApplication.TerminateReply {
        Task {
            await HostStore.unmarkAll()
            app.reply(toApplicationShouldTerminate: true)
        }
        return .terminateLater
    }

    func applicationWillTerminate(_: Notification) {
        Machine.disconnectAll()
    }

    func applicationWillFinishLaunching(_: Notification) {
        UserDefaults.standard.register(defaults: ["NSQuitAlwaysKeepsWindows": true])
        let center = UNUserNotificationCenter.current()
        center.delegate = self
        // macOS asks the user once; later calls answer at once. The Dock badge shows only with `.badge` allowed.
        center.requestAuthorization(options: [.alert, .badge]) { _, _ in }
        // SwiftUI routes `ovvi://` URLs to its scenes, which take none (`handlesExternalEvents`), and drops them.
        NSAppleEventManager.shared().setEventHandler(self, andSelector: #selector(openURL(_:reply:)),
                                                     forEventClass: AEEventClass(kInternetEventClass),
                                                     andEventID: AEEventID(kAEGetURL))
    }

    @objc private func openURL(_ event: NSAppleEventDescriptor, reply _: NSAppleEventDescriptor) {
        if let url = event.paramDescriptor(forKeyword: keyDirectObject)?.stringValue.flatMap(URL.init) {
            application(NSApp, open: [url])
        }
    }

    func applicationDockMenu(_: NSApplication) -> NSMenu? {
        let menu = NSMenu()
        for store in HostStore.all {
            for pane in store.panes {
                guard let state = pane.state, state.calls else { continue }
                let workspace = store.workspace(of: pane.tabID)?.label ?? ""
                let item = NSMenuItem(
                    title: "\(Notifications.title(pane, state)) · \(store.label) · \(workspace)",
                    action: #selector(pick),
                    keyEquivalent: "",
                )
                item.target = self
                item.representedObject = Notifications.id(pane, of: store)
                menu.addItem(item)
            }
        }
        if !menu.items.isEmpty {
            menu.addItem(.separator())
        }
        menu.addItem(withTitle: "New Tab", action: #selector(newTab), keyEquivalent: "").target = self
        return menu
    }

    /// Debug and measure builds claim `ovvi-dev://` and `ovvi-release://`, so neither takes the installed app's URLs.
    func application(_: NSApplication, open urls: [URL]) {
        urls.filter { ["ovvi", "ovvi-dev", "ovvi-release"].contains($0.scheme) }.forEach(WindowPages.float)
        // Files only: `ovvi://float/?…` has a directory path too ("/").
        let folders = urls.filter { $0.isFileURL && $0.hasDirectoryPath }
        if !folders.isEmpty {
            WindowPages.open(folders: folders)
            WindowPages.windows.first?.window?.makeKeyAndOrderFront(nil)
        }
        openWindowIfNone()
    }

    /// AppKit's windows: a restored window joins `WindowPages.windows` only once its pages restore. While the app
    /// is hidden (⌘H), no window is visible.
    private func openWindowIfNone() {
        if !NSApp.windows.contains(where: {
            $0.canBecomeMain && ($0.isVisible || $0.isMiniaturized || NSApp.isHidden)
        }) {
            WindowPages.openWindow?(id: WindowPages.mainScene)
        }
    }

    @objc private func pick(_ item: NSMenuItem) {
        guard let id = item.representedObject as? String else { return }
        NSApp.activate()
        WindowPages.go(to: id)
    }

    @objc private func newTab() {
        NSApp.activate()
        guard let pages = WindowPages.windows.first, let page = pages.current else { return openWindowIfNone() }
        pages.window?.makeKeyAndOrderFront(nil)
        Task { await page.newTab() }
    }

    /// The app posts only for panes the user is not looking at, so banners show while it is active too.
    nonisolated func userNotificationCenter(_: UNUserNotificationCenter, willPresent _: UNNotification) async
        -> UNNotificationPresentationOptions
    {
        [.banner, .list]
    }

    nonisolated func userNotificationCenter(
        _: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
    )
        async
    {
        let id = response.notification.request.identifier
        await MainActor.run {
            NSApp.activate()
            WindowPages.go(to: String(id.trimmingPrefix(Notifications.agent)))
        }
    }
}
