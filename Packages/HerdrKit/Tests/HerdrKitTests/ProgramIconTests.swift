import Foundation
@testable import HerdrKit
import Testing

private let catalog: [ProgramIcon] = {
    let url = repoRoot.appending(path: "resources/icons/catalog.json")
    return (try? JSONDecoder().decode([ProgramIcon].self, from: Data(contentsOf: url))) ?? []
}()

private func icon(agent: String? = nil, _ program: Program? = nil, title: String? = nil) -> String {
    catalog.iconID(agent: agent, program: program, title: title)
}

/// The app draws nothing for a missing image set and the neutral tile for a bad color, silently.
@Test func `every icon has its image set and two tile colors`() throws {
    #expect(catalog.count > 100)
    let hex = /#[0-9a-f]{6}/
    for icon in catalog {
        let set = repoRoot.appending(path: "Ovvi/Assets.xcassets/program.\(icon.id).imageset/\(icon.id).svg")
        #expect(FileManager.default.fileExists(atPath: set.path), "\(icon.id)")
        #expect(
            try hex.wholeMatch(in: icon.tile.background) != nil && hex.wholeMatch(in: icon.tile.glyph) != nil,
            "\(icon.id)",
        )
    }
}

@Test func `herdr's agent wins`() {
    #expect(icon(agent: "claude", Program(name: "node"), title: "π - x") == "claude")
    #expect(icon(agent: "someday", Program(name: "vim")) == "vim")
}

@Test func `the process matches by name, argv0, a Node CLI's script first`() {
    #expect(icon(Program(name: "vim")) == "vim")
    #expect(icon(Program(name: "nvim-wrapper", argv0: "/opt/homebrew/bin/nvim")) == "neovim")
    #expect(icon(Program(name: "-bash")) == "bash")
    #expect(icon(Program(name: "node", argv0: "node", script: "/opt/homebrew/bin/gemini")) == "gemini")
    let piCLI = Program(name: "node", argv0: "node", script: "/x/node_modules/@earendil/pi-coding-agent/dist/cli.js")
    #expect(icon(piCLI) == "pi")
    #expect(icon(Program(name: "node", argv0: "node", script: "server.js")) == "node")
    #expect(icon(Program(name: "vim", script: "git")) == "vim")
}

@Test func `the title's first word matches when nothing else does`() {
    #expect(icon(title: "π - ovvi") == "pi")
    #expect(icon(title: "Claude Code") == "claude")
    #expect(icon(title: "πr squared") == "terminal")
}

@Test func `a shell is the terminal, an unknown program or agent the placeholder`() {
    #expect(icon() == "terminal")
    #expect(icon(Program(name: "zsh", isShell: true), title: "π - x") == "pi")
    #expect(icon(Program(name: "fish", isShell: true)) == "terminal")
    #expect(icon(agent: "someday") == "placeholder")
    #expect(icon(title: "~/code") == "terminal")
    #expect(icon(Program(name: "frobnicate")) == "placeholder")
}
