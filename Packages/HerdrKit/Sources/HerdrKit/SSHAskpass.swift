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

    /// ssh reads the helper's answer without looking at its connection, so a server that stopped waiting (its
    /// LoginGraceTime) leaves ssh waiting too. Its connection can then receive no more: a network socket the server
    /// closed, or the pipes from a ProxyCommand that exited. Not a Unix socket: ssh's agent may close its own. A gone
    /// ssh gave up too.
    static func gaveUp(_ pid: pid_t) -> Bool {
        let size = proc_pidinfo(pid, PROC_PIDLISTFDS, 0, nil, 0)
        var fds = [proc_fdinfo](repeating: proc_fdinfo(), count: Int(max(size, 0)) / MemoryLayout<proc_fdinfo>.stride)
        let filled = proc_pidinfo(pid, PROC_PIDLISTFDS, 0, &fds, size)
        guard filled > 0 else { return true }
        return fds.prefix(Int(filled) / MemoryLayout<proc_fdinfo>.stride).contains { file in
            switch Int32(file.proc_fdtype) {
            case PROX_FDTYPE_SOCKET:
                var info = socket_fdinfo()
                let read = proc_pidfdinfo(pid, file.proc_fd, PROC_PIDFDSOCKETINFO, &info,
                                          Int32(MemoryLayout<socket_fdinfo>.size))
                // SS_CANTRCVMORE in XNU's sys/socketvar.h, not in the SDK.
                return read > 0 && info.psi.soi_family != AF_UNIX && info.psi.soi_state & 0x20 != 0
            case PROX_FDTYPE_PIPE:
                var info = pipe_fdinfo()
                let read = proc_pidfdinfo(pid, file.proc_fd, PROC_PIDFDPIPEINFO, &info,
                                          Int32(MemoryLayout<pipe_fdinfo>.size))
                // PIPE_EOF in XNU's sys/pipe.h, not in the SDK.
                return read > 0 && info.pipeinfo.pipe_status & 0x80 != 0
            default:
                return false
            }
        }
    }
}
