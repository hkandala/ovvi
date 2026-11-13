#!/usr/bin/env python3
"""Runs in the Tart VM before its UI tests (scripts/vm-test.sh): no system alert may take the tests' clicks.

Two of macOS's asks would sit over the tests' window:
- Whether a program may go on capturing the screen ("… is requesting to bypass the system private window picker"), a
  UserNotificationCenter alert, the first time a program captures it and again after a month: a screenshot through
  `tart exec` or ssh, the e2e helper's films. Its answer is replayd's approvals file: a recent alert date and a hint
  date far ahead keep it from asking.
- "App Running in Background", an alert that the open-at-login test brings and that stays until it is closed. The
  answer is usernoted's settings: its notifications are off. (The tests' app asks for none: `-askNotifications NO`.)
A daemon reads its file when it starts and may write it when it stops, so a change goes in between two stops of its
daemon. Prints what it changed.
"""

import datetime
import os
import pathlib
import plistlib
import signal
import subprocess
import time

home = pathlib.Path.home() / "Library/Group Containers"


def restart(daemon):
    """Stops it and waits until it is gone (it may write its file as it ends); launchd starts it again when it is next
    needed."""
    pids = subprocess.run(["pgrep", "-x", daemon], capture_output=True, text=True).stdout.split()
    for pid in pids:
        os.kill(int(pid), signal.SIGTERM)
    for _ in range(20):
        if not any(subprocess.run(["kill", "-0", pid], capture_output=True).returncode == 0 for pid in pids):
            return
        time.sleep(0.1)


def usernoted():
    """usernoted's settings are a preferences domain, which cfprefsd caches: read and write them through it."""
    if not settings.exists():
        return {"apps": []}
    return plistlib.loads(subprocess.run(["defaults", "export", str(settings), "-"], capture_output=True).stdout)


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
allow = 1 << 25  # Allow Notifications
background = "com.apple.BTMNotificationAgent"  # App Running in Background


def allowed():
    return [app for app in usernoted().get("apps", []) if app["bundle-id"] == background and app["flags"] & allow]


if allowed():
    restart("usernoted")
    notes = usernoted()
    for app in notes["apps"]:
        if app["bundle-id"] == background:
            app["flags"] &= ~allow
    subprocess.run(["defaults", "import", str(settings), "-"], input=plistlib.dumps(notes), check=True)
    restart("usernoted")
    print("notifications off:", background, *(["(did not stick)"] if allowed() else []))
