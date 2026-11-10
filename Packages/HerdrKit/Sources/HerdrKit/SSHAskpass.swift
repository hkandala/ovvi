import Foundation

extension SSHExec {
    static let question = "ovvi-askpass "

    /// Per user, 0700, no spaces; a socket path stays under the 104-byte limit.
    static let folder: String = {
        let path = URL.cachesDirectory.appending(path: "ovvi").path(percentEncoded: false)
        try? FileManager.default.createDirectory(atPath: path, withIntermediateDirectories: true,
                                                 attributes: [.posixPermissions: 0o700])
        return path
    }()

    /// A `none` prompt (a security key's touch) only informs: it gets no question.
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
