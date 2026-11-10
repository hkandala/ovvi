#!/usr/bin/env python3
"""make test's settings checks; a failure names what differs.

1. Every Settings search entry (`SettingsSearch(id: "…")`) has its row (`settingsRow("…")` or
   `identifiedSettingsRow("…")`), and every row its entry. The plugins' rows and entries are built from their manifests
   and are not checked here.
2. The UI tests' pinned settings (`shipped` in OvviUITests.swift) are AppSettings' keys with their defaults, but the
   agents' arguments (not in AppSettings) and the settings the tests change through the menus.
"""

import pathlib
import re
import sys

ROOT = pathlib.Path(__file__).resolve().parent.parent
UNPINNED = {"fontSize", "appearance", "interfaceStyle", "focusFollowsMouse"}


def swift(folder):
    return "\n".join(path.read_text() for path in sorted((ROOT / folder).rglob("*.swift")))


def main():
    problems = []
    app = swift("Ovvi")
    entries = set(re.findall(r'SettingsSearch\(id: "([^"]+)"', app))
    rows = set(re.findall(r'\b(?:identifiedS|s)ettingsRow\("([^"]+)"\)', app))
    problems += [f"Settings search entry {id} has no settingsRow" for id in sorted(entries - rows)]
    problems += [f"settingsRow {id} has no Settings search entry" for id in sorted(rows - entries)]

    settings = (ROOT / "Ovvi/Store/AppSettings.swift").read_text()
    stored = dict(re.findall(r'@AppStorage\("([^"]+)"\) var \w+ = (\S+)', settings))
    problems += [f"AppSettings: cannot read {key}'s default" for key in re.findall(r'@AppStorage\("([^"]+)"', settings)
                 if key not in stored]
    if not stored:
        problems.append("no @AppStorage keys in Ovvi/Store/AppSettings.swift")
    tests = (ROOT / "OvviUITests/OvviUITests.swift").read_text()
    found = re.search(r"let shipped = \[(.*?)\]", tests, re.S)
    shipped = dict(re.findall(r'"([^"]+)": "([^"]*)"', found.group(1))) if found else {}
    if not shipped:
        problems.append("no shipped list in OvviUITests/OvviUITests.swift")
    shipped = {key: value for key, value in shipped.items() if not key.startswith("agentArguments.")}
    for key in sorted(set(stored) - UNPINNED - set(shipped)):
        problems.append(f"OvviUITests' shipped does not pin {key}")
    for key in sorted(set(shipped) - set(stored)):
        problems.append(f"OvviUITests' shipped pins {key}, which AppSettings does not hold")
    for key in sorted(set(shipped) & set(stored)):
        default = stored[key]
        want = {"true": "YES", "false": "NO", '""': ""}.get(default, default.rsplit(".", 1)[-1])
        if shipped[key] != want:
            problems.append(f"OvviUITests pins {key} to {shipped[key]!r}, AppSettings' default is {default}")
    for key in sorted(UNPINNED & set(shipped)):
        problems.append(f"OvviUITests pins {key}, which tests change through the menus")
    sys.exit("\n".join(problems) or None)


main()
