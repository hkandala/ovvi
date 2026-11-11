#!/usr/bin/env python3
"""Checks OvviUITests/OwnLaunch.swift: it lists exactly the UI tests that launch the app themselves before they use it.

setUp skips its own launch for them (about 2 s a test). A test is listed when every statement before its first launch
is one that needs no app: a skip, a launch environment, a literal, a helper or herdr call. --write rewrites the list.
"""

import re
import sys
from pathlib import Path

LAUNCH = re.compile(r"(try )?(relaunch|launchRecordingLatency|launchWithoutHerdr)\(")
NO_APP = re.compile("|".join([
    r"try await skipWithoutSSH\(\)$",
    r"app\.launchEnvironment\[",
    r"let \w+ = #?\"",
    r"let \w+ = NSTemporaryDirectory\(\)",
    r"defer \{ try\? FileManager\.default\.removeItem\(",
    r"\+ #?\"",  # the literal's next line
    r"(_ = )?try\?? await Self\.post\(",
    r"addTeardownBlock \{ \[one\] in _ = try\? await Self\.post\(.*\}$",
    r"try await forgetWindows\(\)$",
    r"(let .* = )?try await (shown\()?running\(",
    r"executionTimeAllowance = ",
    r"step\(\"",
    r"for .* in .* \{$",
]))

own = set()
for file in Path("OvviUITests").glob("*.swift"):
    for name, body in re.findall(r"\n    func (test\w+)\([^)]*\)[^{]*\{\n(.*?)\n    \}\n", file.read_text(), re.S):
        for line in (s.strip() for s in body.splitlines()):
            if not line or line.startswith("//"):
                continue
            if LAUNCH.match(line):
                own.add(name)
            if not NO_APP.match(line):
                break
swift = Path("OvviUITests/OwnLaunch.swift")
if "--write" in sys.argv:
    text = swift.read_text()
    swift.write_text(text[:text.index("[\n") + 2] + "".join(f'        "{name}",\n' for name in sorted(own))
                     + text[text.index("    ]"):])
listed = set(re.findall(r"\"(test\w+)\"", swift.read_text()))
if own != listed:
    sys.exit("OvviUITests/OwnLaunch.swift (scripts/check-launches.py --write): " + "; ".join(
        part for part in [f"add {sorted(own - listed)}" if own - listed else "",
                          f"remove {sorted(listed - own)}" if listed - own else ""] if part))
