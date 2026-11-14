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
        // Disk Access): closed now, they are forgotten. A window opened for a folder at launch goes too; the folder
        // waits for the first window.
        if Welcome.firstLaunch {
            NSApp.windows.filter { $0.identifier?.rawValue.hasPrefix(WindowPages.mainScene + "-") == true }
                .forEach { $0.close() }
            WindowReader.lastFrame = nil
        }
        Self.restoredFullScreen = Set(NSApp.windows.filter { $0.styleMask.contains(.fullScreen) }
            .map(ObjectIdentifier.init))
        PluginBuilds.writeTypes()
        Updates.shared.start()
        Task { await DefaultPlugins.shared.install() }
        // After restored windows made their cards and started their processes.
        Task {
            try? await Task.sleep(for: .seconds(3))
            Browser.prewarm()
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
        UserDefaults.standard.register(defaults: ["NSQuitAlwaysKeepsWindows": true, "askNotifications": true])
        let center = UNUserNotificationCenter.current()
        center.delegate = self
        // macOS asks the user once; later calls answer at once. The Dock badge shows only with `.badge` allowed. The UI
        // tests launch with `-askNotifications NO`: no one answers there, and the ask sits over the window's top right
        // and takes their clicks, at every launch.
        if UserDefaults.standard.bool(forKey: "askNotifications") {
            center.requestAuthorization(options: [.alert, .badge]) { _, _ in }
        }
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

    /// macOS hands each build only its own scheme (`ovvi://`, `ovvi-dev://`, `ovvi-release://`, `ovvi-tip://`), and
    /// files.
    func application(_: NSApplication, open urls: [URL]) {
        urls.filter { !$0.isFileURL }.forEach(WindowPages.float)
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
