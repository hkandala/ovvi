#!/usr/bin/env python3
"""Runs in the Tart VM before its UI tests (scripts/vm-test.sh): no system alert may take the tests' clicks.

macOS asks whether a program may go on capturing the screen ("… is requesting to bypass the system private window
picker"), a UserNotificationCenter alert, the first time a program captures it and again after a month: a screenshot
through `tart exec` or ssh, the e2e helper's films. Its answer is replayd's approvals file. A recent alert date and a
hint date far ahead keep it from asking. Prints the programs it approved; replayd reads the file again when it starts.
"""

import datetime
import pathlib
import plistlib
import subprocess

approvals = pathlib.Path.home() / "Library/Group Containers/group.com.apple.replayd/ScreenCaptureApprovals.plist"
# The program macOS asks about is the one responsible: tart's guest agent (a Homebrew path with its version) and ssh's.
agents = [line for line in subprocess.run(["ps", "-axo", "comm="], capture_output=True, text=True).stdout.splitlines()
          if line.endswith("/tart-guest-agent")]
changed = []
found = plistlib.loads(approvals.read_bytes()) if approvals.exists() else {}
ahead = datetime.datetime(2099, 1, 1)  # plistlib wants naive dates, in UTC
for program in {*agents, "/usr/libexec/sshd-keygen-wrapper"}:
    if found.get(program, {}).get("kScreenCapturePrivacyHintDate") != ahead:
        # A future alert date reads as no answer: macOS asks again.
        yesterday = datetime.datetime.now(datetime.timezone.utc).replace(tzinfo=None) - datetime.timedelta(days=1)
        found[program] = {"kScreenCaptureApprovalLastAlerted": yesterday, "kScreenCaptureApprovalLastUsed": yesterday,
                          "kScreenCapturePrivacyHintDate": ahead, "kScreenCapturePrivacyHintPolicy": 2592000,
                          "kScreenCaptureAlertableUsageCount": 1}
        changed.append(program)
if changed:
    approvals.parent.mkdir(parents=True, exist_ok=True)
    approvals.write_bytes(plistlib.dumps(found, fmt=plistlib.FMT_BINARY))
    print("\n".join(changed))
