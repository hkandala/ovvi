#!/usr/bin/env python3
"""Claude Code for the welcome's clips (scripts/record-onboarding.sh): the tests' stand-in (scripts/claude-stand-in.py)
whose scene turns (scripts/welcome-scene) play live instead of all at once, in its terminal as Claude Code draws them
and in the chat view: each step comes after OVVI_CLIP_PACE times its scripted seconds."""
import os
import sys

base = os.path.join(os.path.dirname(os.path.realpath(__file__)), "..", "claude-stand-in.py")
sys.path.insert(0, os.path.dirname(base))
LIVE = r'''
DIM, BOLD, GREEN, ORANGE, OFF = "\x1b[2m", "\x1b[1m", "\x1b[38;5;114m", "\x1b[38;5;173m", "\x1b[0m"


def banner():
    """Claude Code's welcome box and its prompt, on a clear screen."""
    width = 52
    line = lambda text="": "│ " + text + " " * (width - 4 - len(text)) + " │"
    sys.stdout.write("\x1b[2J\x1b[H")
    say(ORANGE + "╭" + "─" * (width - 2) + "╮")
    say(line("✻ Welcome to Claude Code!"))
    say(line())
    say(line("  /help for help, /status for your current setup"))
    say(line())
    say(line("  cwd: " + os.getcwd().replace(os.path.expanduser("~"), "~")))
    say("╰" + "─" * (width - 2) + "╯" + OFF)
    say("")
    sys.stdout.write(DIM + "> " + OFF)
    sys.stdout.flush()


def shown(step):
    """A tool step as Claude Code's terminal shows it: its name and what it works on."""
    given = step["input"]
    what = given.get("file_path") or given.get("command") or given.get("pattern") or ""
    return step["tool"] + "(" + what.replace(os.getcwd() + "/", "") + ")"


def play(text, turn):
    """A scene turn, step by step as it happens; ends idle, or works on in its last tool."""
    pace = float(os.environ.get("OVVI_CLIP_PACE", "0.1"))
    started = time.time()
    write("user", message={"content": text})
    stand_in.report("working")
    for step in turn["steps"]:
        if "text" in step:
            time.sleep(pace * step.get("secs", 2))
            write("assistant", effort="high", message={"model": turn["model"], "content": [
                {"type": "text", "text": step["text"]}]})
            say("⏺ " + step["text"].split("\n")[0] + "\n")
            continue
        tool_id = "toolu_" + uuid.uuid4().hex[:24]
        write("assistant", effort="high", message={"model": turn["model"], "content": [
            {"type": "tool_use", "id": tool_id, "name": step["tool"], "input": step["input"]}]})
        say(GREEN + "⏺" + OFF + " " + BOLD + shown(step) + OFF)
        time.sleep(pace * step.get("secs", 2))
        if "output" in step:
            write("user", toolUseResult=step.get("result"), message={"content": [
                {"type": "tool_result", "tool_use_id": tool_id, "content": step["output"]}]})
            lines = str(step["output"]).split("\n")
            say(DIM + "  ⎿  " + lines[0][:70] + (f" … +{len(lines) - 1} lines" if len(lines) > 1 else "") + OFF + "\n")
    say(ORANGE + "✻" + OFF + " Working… " + DIM + "(esc to interrupt)" + OFF)
    if turn.get("working"):
        return
    write("system", subtype="turn_duration", durationMs=int((time.time() - started) * 1000))
    stand_in.report("idle")


def prompt('''
source = open(base).read()
marks = ["\ndef prompt(", '    say("Claude Code stand-in " + token)\n']
assert all(source.count(mark) == 1 for mark in marks) and "\ndef play(" in source, \
    "claude-stand-in.py changed: update scripts/onboarding/claude.py"
source = source.replace(marks[0], LIVE).replace(marks[1], "    banner()\n")
exec(compile(source, base, "exec"), {"__name__": "__main__", "__file__": os.path.realpath(__file__)})
