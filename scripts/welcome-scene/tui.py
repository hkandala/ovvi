#!/usr/bin/env python3
"""An agent's terminal for the welcome pictures, with no chat: it runs under the agent's name (herdr names a pane's
agent by its foreground process), draws the screen file and reports the state to herdr until its pane closes.
Usage: tui.py <agent> <idle|working|blocked> <screen file>"""
import os
import subprocess
import sys
import tty

sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
import stand_in  # noqa: E402

agent, state, screen = stand_in.run_as(sys.argv[1], __file__)[:3]
tty.setraw(0)
with open(screen) as file:
    # `\e` is an escape, as in printf.
    sys.stdout.write("\x1b[?25l\x1b[2J\x1b[H" + file.read().replace("\\e", "\x1b").replace("\n", "\r\n"))
sys.stdout.flush()
subprocess.run([os.environ["HERDR_BIN_PATH"], "--session", os.environ["HERDR_SESSION"], "pane", "report-agent",
                "--source", "welcome-scene", "--agent", agent, "--state", state, os.environ["HERDR_PANE_ID"]],
               capture_output=True)
# Keys are dropped; a closed pane ends it.
while os.read(0, 1024):
    pass
