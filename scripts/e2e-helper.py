"""Runs herdr API requests for the sandboxed UI tests, which cannot reach herdr's sockets.

Usage: python3 scripts/e2e-helper.py <session>... -- <test command>...
Serves on 127.0.0.1 while the test command runs, then exits with its status.
POST /<session> with one API request line as the body; the reply line comes back.
POST /<session>/control with a terminal id as the body opens `terminal session control` on it
without takeover, closes its stdin at once (which lets go), and gives back what the stream printed
(a frame, or the reason for a refusal); /<session>/takeover does the same with --takeover.
POST /<session>/children lists the session's `terminal session` and `remote-api-bridge` runs, one
command line each.
POST /<session>/stop stops the session; /<session>/start starts its server again, as a user would in a
terminal.
POST /<session>/open-folder with the built app's path as the body makes a folder in /tmp and opens it with the
app (`open -a`), as a drop on the Dock icon does; a launch gets `-session <session>` and the tests' config folder
(a running app ignores `--args`). The folder's path comes back.
POST /<session>/open-url with the built app's path, a newline and an ovvi:// URL opens the URL with that app (`open -g -a`;
a launch gets the tests' config folder).
POST /<session>/file-drag with "x y tx ty" (screen points) as the body makes a file whose name needs shell escaping in
a new folder in /tmp (its one line: ovvi-e2e-dropped), shows its icon at x y in a window of scripts/file-drag.swift
and drags it to tx ty (both points in an Ovvi window). The file's path comes back once a drop took it.
POST /<session>/temporary-file-drag does the same from a new NSIRD_ folder in $TMPDIR/TemporaryItems, as a
screenshot's floating thumbnail drops one. POST /<session>/text-drag drags the text after the points instead.
POST /<session>/usage with a number of seconds as the body measures the tests' app (found by its session) over
that time: its footprint (`footprint`'s summary), its CPU and the session's `terminal session` runs, count and memory;
and the app's, WebKit's and all its processes' count, footprint, CPU, threads and interrupt wake-ups (scripts/usage.swift).
POST /<session>/ssh-drop with an SSH target as the body kills the app's ControlMaster to it (SIGKILL, as a crash
would), and gives back the pids it killed, one per line.
POST /<session>/ssh-stop with an SSH target as the body stops the app's ControlMaster to it (SIGSTOP, as a master that
hangs), on CI only; ssh-drop ends it. The pids come back, one per line.
POST /<session>/ssh-unforward with an SSH target as the body cancels the dynamic forwards (the browser proxy's `-D`)
of the app's ControlMaster to it, on CI only, as a master that lost them; the ports come back, one per line.
POST /<session>/web-kill kills the app's WebKit page processes (SIGKILL, as the system ends one), or with GPU or
Networking as the body its GPU or network process, and gives back the pids it killed, one per line. /<session>/web-stop
stops them instead (SIGSTOP, as a process that hangs), /<session>/web-resume lets them go on, and /<session>/web-pids
only lists them.
POST /<session>/forget-windows removes the Debug build's saved windows ($TMPDIR/dev.ovvi.app.debug.savedState): a test
that restores windows starts from none, not from an earlier test's.
POST /<session>/ssh-hostname with an SSH target and a host name as the body sets that HostName in its ~/.ssh/config
block, on CI only: `<target>.invalid` fails a new connection at once (no network), 192.0.2.1 after its 10 s
ConnectTimeout (a link that is down), 127.0.0.1 is CI's sshd again.
POST /<session>/ssh-forget with an SSH target as the body removes its host key from ~/.ssh/known_hosts, on CI only, so
ssh asks for it again.
POST /<session>/swipe with "x y step steps [pause [vertical [option]]]" as the body posts a two-finger trackpad swipe there (scripts/swipe.swift).
POST /<session>/pinch with "x y step steps" as the body posts a trackpad pinch there (scripts/pinch.swift).
POST /<session>/drag with "x y (x y hold)..." as the body drags the mouse from the first point through the others,
holding at each (scripts/drag.swift).
POST /<session>/press with "x y (x y hold)... tx ty" as the body drags from x y through the others to tx ty and
replies once it holds there; /<session>/release lets go.
POST /<session>/stress with "tabs workspaces panes agents [still]" as the body starts the session afresh and fills it with
scripts/stress.py; its summary comes back. With an empty body it removes the session, so the next tests do not run
beside its shells.
POST /<session>/sample with a number of seconds as the body gives back `sample`'s profile of the app over that time.
POST /<session>/heap gives back `heap`'s summary of the app's malloc heap, the largest classes first.
POST /<session>/record with an .mp4 path as the body films the tests' app's windows in a rect around its floating panel,
the welcome (scripts/record-window.swift: only the app's windows, 2x, 60 fps), and replies once it records;
/<session>/record-stop ends the file. Local only: it needs the screen recording permission.
POST /<session>/welcome with forget as the body removes the Debug build's welcome flag (a first launch); done marks it
done again, as scripts/e2e.sh does.
POST /<session>/pause stops the session's server (SIGSTOP), so the app's writes wait for herdr's answer;
/<session>/resume lets it go on (SIGCONT), as the helper's exit does for every session.
POST /<session>/ssh-connections gives back how many connections the CI sshd (scripts/ci-sshd.sh) has seen, or
"none" where it does not run.
Any session not named on the command line is refused.
Every script that posts events gets the tests' app's pid (OVVI_APP_PID) and refuses a point outside its windows.
"""

import contextlib
import ctypes
import http.server
import os
import re
import shutil
import signal
import socketserver
import subprocess
import sys
import tempfile
import threading
import time

split = sys.argv.index("--")
sessions, command = sys.argv[1:split], sys.argv[split + 1:]
folders = []
held = {}
# Never the user's config folder or agents' stores: a launch installs the default plugins into its config folder.
ISOLATED = ["-configFolder", "/tmp/ovvi-e2e-no-config", "-archivedHome", "/tmp/ovvi-e2e-archived"]
# Compiled once: `swift` interpreting a script takes up to 10 s a swipe on CI.
tools = tempfile.mkdtemp()
folders.append(tools)
# One file each: swiftc takes top-level code only in a single file or main.swift.
for name in ("swipe", "pinch", "drag", "file-drag"):
    with open(f"{tools}/{name}.swift", "w") as joined:
        joined.write(open("scripts/posting.swift").read() + open(f"scripts/{name}.swift").read())
WEB = {"web-kill": signal.SIGKILL, "web-stop": signal.SIGSTOP, "web-resume": signal.SIGCONT, "web-pids": None}
CI_ONLY = {"ssh-stop": "it stops a live ControlMaster", "ssh-unforward": "it changes a live ControlMaster",
           "ssh-forget": "it writes ~/.ssh/known_hosts", "ssh-hostname": "it writes ~/.ssh/config"}
builds = {name: subprocess.Popen(["swiftc", f"{tools}/{name}.swift" if name not in ("usage", "record-window")
                                  else f"scripts/{name}.swift", "-o", f"{tools}/{name}"],
                                 stderr=open(f"{tools}/{name}.log", "wb"))
          for name in ("swipe", "pinch", "drag", "file-drag", "usage", "record-window")}
recordings = {}  # each session's film, from /record until /record-stop


def cpu_seconds(pids):
    """`ps -o time` prints [[h:]m:]s.cc."""
    if not pids:
        return 0.0
    out = subprocess.run(["ps", "-o", "time=", "-p", ",".join(pids)], capture_output=True, text=True).stdout
    return sum(sum(float(part) * 60 ** index for index, part in enumerate(reversed(line.strip().split(":"))))
               for line in out.splitlines() if line.strip())


def usage(session, seconds):
    builds["usage"].wait()
    pid = app_pid()
    pattern = f"^[^ ]*herdr --session {session} terminal session"
    helpers = subprocess.run(["pgrep", "-f", pattern], capture_output=True, text=True).stdout.split()
    start, app_start, helpers_start = time.time(), cpu_seconds([pid]), cpu_seconds(helpers)
    processes = subprocess.run([f"{tools}/usage", pid, str(seconds)], capture_output=True, text=True).stdout
    wall = time.time() - start
    app_cpu, helpers_cpu = cpu_seconds([pid]) - app_start, cpu_seconds(helpers) - helpers_start
    rss = subprocess.run(["ps", "-o", "rss=", "-p", ",".join(helpers)], capture_output=True, text=True).stdout \
        if helpers else ""
    summary = subprocess.run(["footprint", pid], capture_output=True, text=True).stdout.splitlines()
    return "\n".join([f"cpu {100 * app_cpu / wall:.1f}%",
                      f"helpers {len(helpers)} {sum(int(n) for n in rss.split()) // 1024} MB "
                      f"{100 * helpers_cpu / wall:.1f}%"] + processes.splitlines() + summary[:16]).encode()


def app_pid():
    """Never the user's own Ovvi nor another run's."""
    names = "|".join(map(re.escape, sessions))
    pattern = f"/Ovvi Dev.app/Contents/MacOS/Ovvi .*-(session|defaultSession) ({names})( |$)"
    found = subprocess.run(["pgrep", "-nf", pattern], capture_output=True, text=True)
    return found.stdout.strip()


def app_env():
    return {**os.environ, "OVVI_APP_PID": app_pid()}


def masters(target):
    return subprocess.run(["pgrep", "-f", f"ssh -M -N -f .* {target}$"], capture_output=True, text=True).stdout.split()


def signal_server(session, action):
    pids = subprocess.run(["pgrep", "-f", f"^[^ ]*herdr --session {re.escape(session)} server$"],
                          capture_output=True, text=True).stdout.split()
    for pid in pids:
        with contextlib.suppress(ProcessLookupError):
            os.kill(int(pid), signal.SIGSTOP if action == "pause" else signal.SIGCONT)
    return bool(pids)


class Handler(http.server.BaseHTTPRequestHandler):
    def do_POST(self):
        session, _, action = self.path.strip("/").partition("/")
        body = self.rfile.read(int(self.headers.get("Content-Length", 0)))
        if session not in sessions:
            status, reply = 403, f"refusing session '{session}'".encode()
        elif action in ("control", "takeover") and not re.fullmatch(rb"\w[\w-]*", body):
            status, reply = 400, b"the body must be a terminal id"
        elif action == "ssh-hostname" and not re.fullmatch(rb"\w[\w-]* [\w.-]+", body):
            status, reply = 400, b"the body must be an SSH target and a host name"
        elif action.startswith("ssh-") and action not in ("ssh-connections", "ssh-hostname") \
                and not re.fullmatch(rb"\w[\w-]*", body):
            status, reply = 400, b"the body must be an SSH target"
        elif action == "pinch" and not re.fullmatch(rb"-?[\d.]+( -?[\d.]+){3}", body):
            status, reply = 400, b"the body must be x y step steps"
        elif action == "swipe" and not re.fullmatch(rb"-?[\d.]+( -?[\d.]+){3,6}", body):
            status, reply = 400, b"the body must be x y step steps [pause [vertical [option]]]"
        elif action == "stress" and not re.fullmatch(rb"(\d+ \d+ \d+ \d+( still)?)?", body):
            status, reply = 400, b"the body must be tabs workspaces panes agents [still], or empty"
        elif action == "stress":
            # Down first: a run cut short (a timeout, a test retried) may have left it.
            run = subprocess.run(["scripts/herdr-session.sh", "down", session], capture_output=True)
            if run.returncode == 0 and body:
                run = subprocess.run(["scripts/herdr-session.sh", "up", session], capture_output=True)
            if run.returncode == 0 and body:
                tabs, workspaces, panes, agents, *still = body.decode().split()
                # This Mac's 511 terminals are shared with the user's own herdr sessions and programs.
                panes = panes if os.environ.get("CI") == "true" else str(min(int(panes), 200))
                try:
                    run = subprocess.run(["python3", "scripts/stress.py", session, tabs, workspaces, "--panes",
                                          panes, "--agents", agents] + [f"--{word}" for word in still],
                                         capture_output=True, timeout=280)
                except subprocess.TimeoutExpired as error:
                    run = subprocess.CompletedProcess(error.cmd, 1, b"", b"stress.py took over 280 s")
            status, reply = (200, run.stdout) if run.returncode == 0 else (500, run.stderr)
        elif action == "sample" and not re.fullmatch(rb"\d+", body):
            status, reply = 400, b"the body must be seconds"
        elif action in ("sample", "heap"):
            pid = app_pid()
            argv = ["sample", pid, body.decode()] if action == "sample" else ["heap", "-s", "-H", "-q", pid]
            # A bound for a hung tool, not a measure: `heap` walks every malloc node, 37 s at the stress test's 400
            # panes on CI, and over 60 s on a runner half as fast.
            limit = 180
            try:
                run = subprocess.run(argv, capture_output=True, timeout=limit)
                status, reply = (200, run.stdout) if run.returncode == 0 else (500, run.stderr)
            except subprocess.TimeoutExpired:
                status, reply = 500, f"{action} took over {limit} s".encode()
        elif action == "drag" and not re.fullmatch(rb"-?[\d.]+ -?[\d.]+( -?[\d.]+ -?[\d.]+ [\d.]+)+", body):
            status, reply = 400, b"the body must be x y (x y hold)..."
        elif action in ("file-drag", "temporary-file-drag", "text-drag") and not re.fullmatch(
                rb"-?[\d.]+( -?[\d.]+){3}" + (rb" .+" if action == "text-drag" else b""), body):
            status, reply = 400, b"the body must be x y tx ty"
        elif action == "press" and not re.fullmatch(rb"-?[\d.]+ -?[\d.]+( -?[\d.]+ -?[\d.]+ [\d.]+)* -?[\d.]+ -?[\d.]+",
                                                    body):
            status, reply = 400, b"the body must be x y (x y hold)... tx ty"
        elif action == "release" and session not in held:
            status, reply = 400, b"no drag held"
        elif action in (*builds, "press", "temporary-file-drag", "text-drag") and any(
                [build.wait() for build in builds.values()]):
            status, reply = 500, b"".join(open(f"{tools}/{name}.log", "rb").read() for name in builds)
        elif action in ("swipe", "pinch", "drag"):
            run = subprocess.run([f"{tools}/{action}"] + body.decode().split(), capture_output=True, timeout=120,
                                 env=app_env())
            status, reply = (200, b"") if run.returncode == 0 else (500, run.stderr)
        elif action == "press":
            run = subprocess.Popen([f"{tools}/drag"] + body.decode().split() + ["-1"], env=app_env(),
                                   stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
            if run.stdout.readline():  # "held": over tx ty
                held[session] = run
                status, reply = 200, b""
            else:
                status, reply = 500, run.communicate(timeout=10)[1]
        elif action == "kill-app":
            # The kill XCUITest's terminate sends too (no quit), but it then checks for the exit once a second.
            pid = app_pid()
            if pid:
                with contextlib.suppress(ProcessLookupError):
                    os.kill(int(pid), signal.SIGKILL)
            status, reply = 200, pid.encode()
        elif action == "welcome" and body not in (b"forget", b"done"):
            status, reply = 400, b"the body must be forget or done"
        elif action == "welcome":
            # The tests' Debug defaults only, never the user's Ovvi: forget is a first launch, done is scripts/e2e.sh's.
            argv = ["delete", "dev.ovvi.app.debug", "welcomeDone"] if body == b"forget" else \
                ["write", "dev.ovvi.app.debug", "welcomeDone", "-bool", "YES"]
            subprocess.run(["defaults", *argv], capture_output=True)
            status, reply = 200, b""
        elif action == "record" and os.environ.get("CI") == "true":
            status, reply = 403, b"local only: it needs the screen recording permission"
        elif action == "record":
            builds["record-window"].wait()
            if session in recordings:  # an earlier film never stopped
                old = recordings.pop(session)
                old.kill()
                old.wait()
            run = subprocess.Popen([f"{tools}/record-window", app_pid(), body.decode()], stdin=subprocess.PIPE,
                                   stdout=subprocess.PIPE, stderr=subprocess.PIPE)
            if run.stdout.readline():  # "recording WxH"
                recordings[session] = run
                status, reply = 200, b""
            else:
                status, reply = 500, run.communicate(timeout=10)[1]
        elif action == "record-stop":
            run = recordings.pop(session, None)
            try:
                _, error = run.communicate(b"", timeout=110) if run else (b"", b"no recording")  # the crop's encode
                status, reply = (200, b"") if run and run.returncode == 0 else (500, error)
            except subprocess.TimeoutExpired:
                run.kill()
                status, reply = 500, b"the recording did not end in 110 s"
        elif action == "release":
            run = held.pop(session)
            _, error = run.communicate(b"\n", timeout=30)
            status, reply = (200, b"") if run.returncode == 0 else (500, error)
        elif action in CI_ONLY and os.environ.get("CI") != "true":
            status, reply = 403, f"CI only: {CI_ONLY[action]}".encode()
        elif action in ("ssh-drop", "ssh-stop"):
            pids = masters(body.decode())
            for pid in pids:
                with contextlib.suppress(ProcessLookupError):
                    os.kill(int(pid), signal.SIGKILL if action == "ssh-drop" else signal.SIGSTOP)
            status, reply = 200, "".join(f"{pid}\n" for pid in pids).encode()
        elif action == "ssh-unforward":
            target, ports = body.decode(), []
            for pid in masters(target):
                command = subprocess.run(["ps", "-o", "command=", "-p", pid], capture_output=True, text=True).stdout
                socket = command.split(" -S ", 1)[1].split()[0]
                listening = subprocess.run(["lsof", "-a", "-nP", "-p", pid, "-iTCP", "-sTCP:LISTEN", "-Fn"],
                                           capture_output=True, text=True).stdout
                for port in re.findall(r"^n127\.0\.0\.1:(\d+)$", listening, re.M):
                    subprocess.run(["ssh", "-F", "/dev/null", "-S", socket, "-O", "cancel", "-D", f"127.0.0.1:{port}",
                                    "--", target], capture_output=True)
                    ports.append(port)
            status, reply = 200, "\n".join(ports).encode()
        elif action in WEB and body not in (b"", b"GPU", b"Networking"):
            status, reply = 400, b"the body must be empty (page processes), GPU or Networking"
        elif action in WEB:
            app = int(app_pid() or 0)
            responsible = ctypes.CDLL(None).responsibility_get_pid_responsible_for_pid
            kind = f"com.apple.WebKit.{body.decode() or 'WebContent'}"
            found = subprocess.run(["pgrep", "-f", f"{kind}.xpc/"], capture_output=True, text=True).stdout
            pids = [pid for pid in map(int, found.split()) if app and responsible(pid) == app]
            for pid in pids:
                if action != "web-pids":
                    os.kill(pid, WEB[action])
            status, reply = 200, "".join(f"{pid}\n" for pid in pids).encode()
        elif action == "forget-windows":
            shutil.rmtree(os.path.join(tempfile.gettempdir(), "dev.ovvi.app.debug.savedState"), ignore_errors=True)
            status, reply = 200, b""
        elif action == "ssh-hostname":
            config, (target, name) = os.path.expanduser("~/.ssh/config"), body.decode().split()
            text = open(config).read()
            new = re.sub(rf"(?m)^(Host {re.escape(target)}\n  HostName ).*$", lambda m: m.group(1) + name, text)
            with open(config, "w") as file:
                file.write(new)
            status, reply = (200, b"") if f"Host {target}\n  HostName {name}\n" in new else (500, b"no such Host block")
        elif action == "ssh-forget":
            run = subprocess.run(["ssh-keygen", "-R", body.decode()], capture_output=True)
            status, reply = (200, b"") if run.returncode == 0 else (500, run.stderr)
        elif action == "ssh-connections":
            try:
                with open("/tmp/ovvi-sshd/sshd.log") as log:
                    status, reply = 200, str(log.read().count("Connection from")).encode()
            except FileNotFoundError:
                status, reply = 200, b"none"
            except OSError as error:
                status, reply = 500, str(error).encode()
        elif action == "open-folder" and not body.endswith(b".app"):
            status, reply = 400, b"the body must be an app's path"
        elif action == "open-folder":
            folder = tempfile.mkdtemp(prefix="ovvi-e2e-drop-", dir="/tmp")
            folders.append(folder)
            run = subprocess.run(["open", "--env", "npm_config_offline=true", "-a", body.decode(), folder, "--args",
                                  "-session", session,
                                  "-ApplePersistenceIgnoreState", "YES", *ISOLATED],
                                 capture_output=True, timeout=10)
            status, reply = (200, folder.encode()) if run.returncode == 0 else (500, run.stderr)
        elif action == "open-url" and not re.fullmatch(rb"[^\n]+\.app\novvi://\S+", body):
            status, reply = 400, b"the body must be an app's path, a newline and an ovvi:// URL"
        elif action == "open-url":
            # -a: LaunchServices may know other builds of the app.
            app, url = body.decode().split("\n")
            run = subprocess.run(["open", "--env", "npm_config_offline=true", "-g", "-a", app, url, "--args",
                                  "-machines", "[]", *ISOLATED],
                                 capture_output=True, timeout=10)
            status, reply = (200, b"") if run.returncode == 0 else (500, run.stderr)
        elif action in ("file-drag", "temporary-file-drag"):
            if action == "file-drag":
                folder = tempfile.mkdtemp(prefix="ovvi-e2e-file-", dir="/tmp")
            else:
                items = os.path.join(tempfile.gettempdir(), "TemporaryItems")
                os.makedirs(items, exist_ok=True)
                folder = tempfile.mkdtemp(prefix="NSIRD_ovvi-e2e_", dir=items)
            folders.append(folder)
            path = os.path.join(folder, "drop me's (1).txt")
            with open(path, "w") as file:
                file.write("ovvi-e2e-dropped\n")
            x, y, tx, ty = body.decode().split()
            source = subprocess.run([f"{tools}/file-drag", path, x, y, tx, ty], capture_output=True, timeout=30,
                                    env=app_env())
            status, reply = (200, path.encode()) if source.returncode == 0 else (
                500, source.stderr or b"the drop was refused")
        elif action == "text-drag":
            x, y, tx, ty, text = body.decode().split(" ", 4)
            source = subprocess.run([f"{tools}/file-drag", f"text:{text}", x, y, tx, ty], capture_output=True,
                                    timeout=30, env=app_env())
            status, reply = (200, b"") if source.returncode == 0 else (500, source.stderr or b"the drop was refused")
        elif action in ("pause", "resume"):
            status, reply = (200, b"") if signal_server(session, action) else (500, b"no server")
        elif action == "usage":
            status, reply = 200, usage(session, float(body or b"10"))
        elif action == "start":
            env = {k: v for k, v in os.environ.items() if not k.startswith("HERDR_")}
            subprocess.Popen(["herdr", "--session", session, "server"], env=env, stdin=subprocess.DEVNULL,
                             stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, start_new_session=True)
            status, reply = 200, b""
        elif action in ("", "control", "takeover", "children", "stop"):
            argv = ["herdr", "--session", session]
            if action in ("control", "takeover"):
                argv += ["terminal", "session", "control", body.decode(), "--cols", "80", "--rows", "24"]
                argv += ["--takeover"] if action == "takeover" else []
                body = b""
            elif action == "children":
                # Tests ask while no other request of theirs runs, so none of these is the helper's own. Anchored:
                # the shell that wraps an `observe` run is not a run of its own.
                argv = ["pgrep", "-lf", f"^[^ ]*herdr --session {session} (terminal session|remote-api-bridge)"]
            elif action == "stop":
                argv = ["herdr", "session", "stop", session]
            else:
                argv += ["remote-api-bridge"]
            try:
                run = subprocess.run(argv, input=body, capture_output=True, timeout=10)
                # pgrep exits 1 when it finds none.
                ok = run.returncode == 0 or action == "children" and run.returncode == 1
                status, reply = (200, run.stdout) if ok else (500, run.stderr)
            except Exception as error:  # a timeout or no herdr: tell the test, keep serving
                status, reply = 500, str(error).encode()
        else:
            status, reply = 404, f"no action '{action}'".encode()
        self.send_response(status)
        self.send_header("Content-Length", str(len(reply)))
        self.end_headers()
        self.wfile.write(reply)

    def log_message(self, *args):
        pass


# Not HTTPServer: its getfqdn() lookup raises macOS's Local Network prompt. Threading: a test's `sample` runs while
# its swipes do.
server = socketserver.ThreadingTCPServer(("127.0.0.1", 0), Handler)
server.daemon_threads = True
threading.Thread(target=server.serve_forever, daemon=True).start()
# xcodebuild passes TEST_RUNNER_* to the tests without the prefix.
# herdr's path: the agent test's stand-in login shell has no profile to find it.
env = {**os.environ, "TEST_RUNNER_OVVI_HELPER": f"http://127.0.0.1:{server.server_address[1]}",
       "TEST_RUNNER_OVVI_HERDR": shutil.which("herdr") or "",
       **{f"TEST_RUNNER_OVVI_SESSION{n if n > 1 else ''}": name for n, name in enumerate(sessions, 1)}}
# The tools' builds take the cores for a minute on CI: done before the first test, as a prebuilt run has no app build
# beside them.
start = time.monotonic()
for build in builds.values():
    build.wait()
print(f"e2e-helper: tools built in {time.monotonic() - start:.1f} s", file=sys.stderr)
status = subprocess.run(command, env=env).returncode
# A film a test never stopped would go on filming the display.
for run in recordings.values():
    run.kill()
# A run cut short between a pause and its resume leaves no stopped server, which the cleanup's stop would wait on.
for name in sessions:
    signal_server(name, "resume")
for folder in folders:
    shutil.rmtree(folder, ignore_errors=True)
sys.exit(status)
