import GhosttyTerminal
import SwiftUI

struct AppSettings: DynamicProperty {
    @AppStorage("appearance") var appearance = Appearance.dark
    @AppStorage("interfaceStyle") var style = InterfaceStyle.glass
    @AppStorage("fontSize") var fontSize = PaneTerminal.fontSize
    @AppStorage("focusFollowsMouse") var followMouse = false
    @AppStorage("newPaneOpens") var newPaneOpens = ""
    @AppStorage("notifyNeedsYou") var notifyNeedsYou = true
    @AppStorage("notifyFinished") var notifyFinished = true
    @AppStorage("notifyFromAgents") var notifyFromAgents = true
    @AppStorage("terminalFont") var terminalFont = ""
    @AppStorage("cursorStyle") var cursorStyle = TerminalCursorStyle.block
    @AppStorage("cursorBlink") var cursorBlink = true
    @AppStorage("optionKey") var optionKey = OptionKey.characters
    @AppStorage("copyOnSelect") var copyOnSelect = false
    @AppStorage("agentView") var agentView = AgentView.terminal
    @AppStorage("showClosedSessions") var showClosed = true
    @AppStorage("spaceOrder") var spaceOrder = SpaceOrder.manual

    var terminal: [String] {
        [terminalFont, "\(fontSize)", cursorStyle.rawValue, "\(cursorBlink)", optionKey.rawValue, "\(copyOnSelect)"]
    }
}

enum Appearance: String {
    case auto, light, dark
}

enum InterfaceStyle: String {
    case glass, classic
}

enum OptionKey: String, CaseIterable {
    case characters, meta, left

    /// libghostty's `macos-option-as-alt`.
    var ghostty: String {
        switch self {
        case .characters: "false"
        case .meta: "true"
        case .left: "left"
        }
    }
}

enum AgentView: String {
    case terminal, chat
}

@MainActor
extension UserDefaults {
    /// The sidebar's state, per build and config folder, so a test's `-configFolder` keeps its writes out of the
    /// user's. Not a suite at a path: once its file exists, a new process's writes read back the prior value and notify
    /// no view.
    static let sidebar = UserDefaults(suiteName: "\(Bundle.main.bundleIdentifier ?? "dev.ovvi.app").sidebar."
        + Registry.config.path.replacing("/", with: "_")) ?? .standard
}
