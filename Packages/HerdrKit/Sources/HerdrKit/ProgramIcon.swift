import Foundation

public struct ProgramIcon: Decodable, Sendable {
    public let id: String
    public let tile: Tile
    let match: Match

    public struct Tile: Decodable, Sendable {
        public let background: String
        public let glyph: String
    }

    struct Match: Decodable {
        let agent: [String]?
        let process: [String]?
        let titlePrefix: [String]?
        let scriptSuffix: [String]?
    }
}

public extension [ProgramIcon] {
    func iconID(agent: String?, program: Program?, title: String?) -> String {
        func find(_ hit: (ProgramIcon.Match) -> Bool) -> String? {
            first { hit($0.match) }?.id
        }
        if let agent, let id = find({ $0.agent?.contains(agent) == true }) {
            return id
        }
        if let program, !program.isShell {
            // A login shell's argv0 starts with `-`. Not `URL(filePath:)`: for a bare name it reads the working
            // folder (getcwd), for each tile's icons in each overview frame.
            let base = { (path: String) in String((path.split(separator: "/").last ?? "").trimmingPrefix("-")) }
            var names = [program.name, program.argv0].compactMap(\.self).map(base)
            // A Node CLI (`pi`) is its script, not `node`: the package's path, else the name of the bin link that
            // started it (`gemini`).
            if let script = program.script, names.contains(where: Program.runtimes.contains) {
                if let id = find({ $0.scriptSuffix?.contains { script.hasSuffix($0) } == true }) {
                    return id
                }
                names.insert(base(script), at: 0)
            }
            for name in names {
                if let id = find({ $0.process?.contains(name) == true }) {
                    return id
                }
            }
        }
        if let title, let id = find({ $0.titlePrefix?.contains { title == $0 || title.hasPrefix($0 + " ") } == true }) {
            return id
        }
        return agent == nil && program?.isShell != false ? "terminal" : "placeholder"
    }
}
