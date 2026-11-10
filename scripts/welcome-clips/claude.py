#!/usr/bin/env python3
"""Claude Code for the welcome's clips (scripts/welcome-clips.sh): the tests' stand-in (scripts/claude-stand-in.py)
whose scene turns (scripts/welcome-scene) play live instead of all at once, so a clip films the chat as it grows: each
step comes after OVVI_CLIP_PACE times its scripted seconds."""
import os

base = os.path.join(os.path.dirname(os.path.realpath(__file__)), "..", "claude-stand-in.py")
LIVE = '''
def play(text, turn):
    """A scene turn, step by step as it happens; ends idle, or works on in its last tool."""
    pace = float(os.environ.get("OVVI_CLIP_PACE", "0.1"))
    started = time.time()
    write("user", message={"content": text})
    report("working")
    for step in turn["steps"]:
        if "text" in step:
            time.sleep(pace * step.get("secs", 2))
            write("assistant", effort="high", message={"model": turn["model"], "content": [
                {"type": "text", "text": step["text"]}]})
            continue
        tool_id = "toolu_" + uuid.uuid4().hex[:24]
        write("assistant", effort="high", message={"model": turn["model"], "content": [
            {"type": "tool_use", "id": tool_id, "name": step["tool"], "input": step["input"]}]})
        time.sleep(pace * step.get("secs", 2))
        if "output" in step:
            write("user", toolUseResult=step.get("result"), message={"content": [
                {"type": "tool_result", "tool_use_id": tool_id, "content": step["output"]}]})
    if turn.get("working"):
        return
    write("system", subtype="turn_duration", durationMs=int((time.time() - started) * 1000))
    report("idle")


def prompt('''
source = open(base).read()
mark = "\ndef prompt("
assert source.count(mark) == 1 and "\ndef play(" in source, "claude-stand-in.py changed: update welcome-clips/claude.py"
exec(compile(source.replace(mark, LIVE), base, "exec"), {"__name__": "__main__", "__file__": os.path.realpath(__file__)})
