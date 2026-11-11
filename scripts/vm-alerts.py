#!/usr/bin/env python3
"""Runs in the Tart VM before its UI tests (scripts/vm-test.sh): no system alert may take the tests' clicks.

Two of macOS's asks would sit over the tests' window:
- Whether a program may go on capturing the screen ("… is requesting to bypass the system private window picker"), a
  UserNotificationCenter alert, the first time a program captures it and again after a month: a screenshot through
  `tart exec` or ssh, the e2e helper's films. Its answer is replayd's approvals file: a recent alert date and a hint
  date far ahead keep it from asking.
- Whether the tests' app may send notifications, a banner over the window's top right until it is answered. The
  answer is usernoted's settings: the app's notifications are off, which also keeps its banners off the tests, and so
  are those of "App Running in Background", an alert that stays until it is closed.
A daemon reads its file when it starts and may write it when it stops, so a change goes in between two stops of its
daemon. Prints what it changed.
"""

import datetime
import os
import pathlib
import plistlib
import signal
import subprocess

home = pathlib.Path.home() / "Library/Group Containers"


def restart(daemon):
    """Stops it; launchd starts it again when it is next needed."""
    for pid in subprocess.run(["pgrep", "-x", daemon], capture_output=True, text=True).stdout.split():
        os.kill(int(pid), signal.SIGTERM)


approvals = home / "group.com.apple.replayd/ScreenCaptureApprovals.plist"
# The program macOS asks about is the one responsible: tart's guest agent (a Homebrew path with its version) and ssh's.
running = subprocess.run(["ps", "-axo", "comm="], capture_output=True, text=True).stdout.splitlines()
agents = [os.path.realpath(line) for line in running if line.endswith("/tart-guest-agent")]
found = plistlib.loads(approvals.read_bytes()) if approvals.exists() else {}
ahead = datetime.datetime(2099, 1, 1)  # plistlib wants naive dates, in UTC
# A future alert date reads as no answer: macOS asks again.
yesterday = datetime.datetime.now(datetime.timezone.utc).replace(tzinfo=None) - datetime.timedelta(days=1)
changed = [program for program in {*agents, "/usr/libexec/sshd-keygen-wrapper"}
           if found.get(program, {}).get("kScreenCapturePrivacyHintDate") != ahead]
for program in changed:
    found[program] = {"kScreenCaptureApprovalLastAlerted": yesterday, "kScreenCaptureApprovalLastUsed": yesterday,
                      "kScreenCapturePrivacyHintDate": ahead, "kScreenCapturePrivacyHintPolicy": 2592000,
                      "kScreenCaptureAlertableUsageCount": 1}
if changed:
    restart("replayd")
    approvals.parent.mkdir(parents=True, exist_ok=True)
    approvals.write_bytes(plistlib.dumps(found, fmt=plistlib.FMT_BINARY))
    restart("replayd")
    print("screen capture approved:", ", ".join(sorted(changed)))

settings = home / "group.com.apple.usernoted/Library/Preferences/group.com.apple.usernoted.plist"
notes = plistlib.loads(settings.read_bytes())
allow = 1 << 25  # Allow Notifications
# The tests' app, asked once in this VM and answered Don't Allow (auth is the options it asks for: alert, badge), and
# "App Running in Background", which the open-at-login test brings.
off = {"dev.ovvi.app.debug": {"auth": 5, "flags": 0x1080200E, "content_visibility": 0, "grouping": 0},
       "com.apple.BTMNotificationAgent": {}}
apps = {app["bundle-id"]: app for app in notes["apps"]}
changed = [name for name, new in off.items()
           if (name not in apps and new) or apps.get(name, {}).get("flags", 0) & allow]
if changed:
    restart("usernoted")
    notes = plistlib.loads(settings.read_bytes())
    for name in changed:
        app = next((app for app in notes["apps"] if app["bundle-id"] == name), None)
        if app is None:
            notes["apps"].append({"bundle-id": name, **off[name]})
        else:
            app["flags"] &= ~allow
    settings.write_bytes(plistlib.dumps(notes, fmt=plistlib.FMT_BINARY))
    restart("usernoted")
    print("notifications off:", ", ".join(changed))
