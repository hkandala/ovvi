import Foundation

extension SSHExec {
    /// The remote command envelope (talking-to-herdr#run-and-dial): the machine's login shell may be bash, zsh or
    /// fish, so it gets only base64, which every shell passes through; `sh` decodes and runs the quoted argv.
    public static func envelope(_ argv: [String]) -> String {
        #"sh -c 'eval "$(printf %s "$1" | base64 -d)"' sh "# + Data(quoted(argv).utf8).base64EncodedString()
    }

    /// The argv as one POSIX `sh` command, every element single-quoted.
    static func quoted(_ argv: [String]) -> String {
        argv.map { "'" + $0.replacingOccurrences(of: "'", with: #"'\''"#) + "'" }.joined(separator: " ")
    }

    /// The askpass helper's mark on a question it passes to the app (`start`).
    static let question = "ovvi-askpass "

    /// The sockets' folder: per user, 0700, no spaces; a socket path stays under the 104-byte limit.
    static let folder: String = {
        let path = URL.cachesDirectory.appending(path: "ovvi").path(percentEncoded: false)
        try? FileManager.default.createDirectory(atPath: path, withIntermediateDirectories: true,
                                                 attributes: [.posixPermissions: 0o700])
        return path
    }()

    /// The askpass helper, written beside the sockets on the first connect that may ask. A `none` prompt (a
    /// security key's touch) only informs: it gets no question.
    static let askpass: String = {
        let path = folder + "/askpass"
        let script = """
        #!/bin/sh
        [ "$SSH_ASKPASS_PROMPT" = none ] && exit 0
        printf '\(question)%s\\n' "$(printf %s "$1" | base64 | tr -d '\\n')" >&2
        IFS= read -r answer || exit 1
        printf '%s\\n' "$answer"

        """
        FileManager.default.createFile(atPath: path, contents: Data(script.utf8),
                                       attributes: [.posixPermissions: 0o700])
        return path
    }()
}
