import contextlib
import json
import os
import select
import signal
import subprocess
import sys
import termios
import tty

folder = os.path.join(os.environ.get("TMPDIR", "/tmp"), "ovvi-stand-in")
agent = None  # the name `run_as` runs as: the agent `report` names
os.makedirs(folder, exist_ok=True)


def run_as(name, script):
    """herdr prompts an agent only while a process of its name runs in the foreground. A framework build's `python3`
    runs its Python.app, which would drop the name: link to that one. OVVI_STAND_IN_TITLE=1: no arguments in its
    process's own, as a Node CLI that sets its process title (npm's pi)."""
    global agent
    agent = name
    if os.environ.get("OVVI_STAND_IN") != "1":
        os.environ["OVVI_STAND_IN"] = "1"
        app = os.path.join(sys.base_prefix, "Resources/Python.app/Contents/MacOS/Python")
        link = os.path.join(folder, name)
        if os.path.islink(link):
            os.remove(link)
        os.symlink(app if os.path.exists(app) else os.path.realpath(sys.executable), link)
        rest = sys.argv[1:]
        if os.environ.get("OVVI_STAND_IN_TITLE") == "1":
            os.environ["OVVI_STAND_IN_ARGS"], rest = json.dumps(rest), []
        os.execv(link, [link, os.path.abspath(script)] + rest)
    return json.loads(os.environ.pop("OVVI_STAND_IN_ARGS", "null")) or sys.argv[1:]


def herdr(*arguments):
    subprocess.run([os.environ["HERDR_BIN_PATH"], "--session", os.environ["HERDR_SESSION"], "pane", *arguments,
                    os.environ["HERDR_PANE_ID"]], capture_output=True)


def report(state):
    herdr("report-agent", "--source", "ovvi-e2e", "--agent", agent, "--state", state)


def say(text):
    sys.stdout.write(text.replace("\n", "\r\n") + "\r\n")
    sys.stdout.flush()


def key(timeout=None):
    if not select.select([0], [], [], timeout)[0]:
        return ""
    data = os.read(0, 4096).decode(errors="replace")
    return data.replace("\x1b[200~", "").replace("\x1b[201~", "")


@contextlib.contextmanager
def terminal(cleanup):
    """The terminal raw with bracketed paste on, as the agents have it: herdr's agent.prompt pastes, then presses Enter.

    A closed pane hangs up: `cleanup` runs first, as on Ctrl-C, since a hung-up terminal takes no settings. A second
    hang-up would stop it halfway."""
    signal.signal(signal.SIGHUP, lambda *_: sys.exit(0))
    attributes = termios.tcgetattr(0)
    tty.setraw(0)
    sys.stdout.write("\x1b[?2004h")
    try:
        yield
    finally:
        signal.signal(signal.SIGHUP, signal.SIG_IGN)
        cleanup()
        termios.tcsetattr(0, termios.TCSADRAIN, attributes)
