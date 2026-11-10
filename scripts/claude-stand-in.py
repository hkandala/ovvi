#!/usr/bin/env python3
"""Claude Code's stand-in for the chat view's UI tests (CI has no Claude Code).

Started by the chooser with Ovvi's flags (`--session-id T --settings <json>`), it runs the settings' own hooks,
writes a transcript in Claude Code's format, reports its state to herdr and answers prompts on its terminal: "wait"
shows a dialog until 1 is typed, "ask" asks a question through the PermissionRequest hook, "slow" works until Esc,
"mute" drops the next prompt, "long" gets a command with 200 lines of output, "big" writes 330 KB of lines the chat
skips (as a real session's API records), "steps" gets a reply, a command, a reply, two commands and a reply, "many"
writes 150 more turns (a long session; "many 25" that many, "many 10 30" 10 with 30 more paragraphs each), a prompt of
OVVI_STAND_IN_SCENE's turns plays that turn (scripts/welcome-scene/turns.py), anything else gets one command and the
reply "Echo: <prompt>". Ctrl-C clears the line, and on an empty one asks for another;
"/exit" quits, after OVVI_STAND_IN_EXIT_HOOKS seconds when set (as Claude Code runs its SessionEnd hooks). Started
without flags it reports its session to herdr (as herdr's Claude Code integration does) and keeps its transcript, which
`--resume <session>` goes on with.
"""
import json
import os
import re
import shutil
import subprocess
import sys
import time
import uuid

import stand_in
from stand_in import folder, herdr, key, say, terminal

args = stand_in.run_as("claude", __file__)
settings = args[args.index("--settings") + 1] if "--settings" in args else '{"hooks":{}}'
hooks = json.loads(settings)["hooks"]
resumed = "--resume" in args
token = args[args.index("--resume" if resumed else "--session-id") + 1] if resumed or "--session-id" in args \
    else str(uuid.uuid4())
transcript = os.path.join(folder, token + ".jsonl")
# OVVI_STAND_IN_FAIL_RESUME=<file>: its first resume with Ovvi's flags exits at once (a build that refuses them).
failed = os.environ.get("OVVI_STAND_IN_FAIL_RESUME")
if failed and resumed and "--settings" in args and not os.path.exists(failed):
    open(failed, "w").close()
    sys.exit("error: unknown option")
scene = json.load(open(os.environ["OVVI_STAND_IN_SCENE"]))["claude"] if os.environ.get("OVVI_STAND_IN_SCENE") else {}


def hook(event, payload):
    for group in hooks.get(event, []):
        for command in group["hooks"]:
            return subprocess.run(["sh", "-c", command["command"]], input=json.dumps(payload),
                                  capture_output=True, text=True).stdout
    return ""


def write(kind, at=None, **fields):
    line = {"type": kind, "uuid": str(uuid.uuid4()), "cwd": os.getcwd(),
            "timestamp": time.strftime("%Y-%m-%dT%H:%M:%S.000Z", time.gmtime(at)), **fields}
    with open(transcript, "a") as file:
        file.write(json.dumps(line) + "\n")


def tool(command, output):
    tool_id = "toolu_" + uuid.uuid4().hex[:12]
    write("assistant", message={"model": "claude-stand-in", "content": [
        {"type": "tool_use", "id": tool_id, "name": "Bash", "input": {"command": command}}]})
    if output is not None:
        write("user", message={"content": [{"type": "tool_result", "tool_use_id": tool_id, "content": output}]})


def reply(text, started):
    write("assistant", effort="high", message={"model": "claude-stand-in", "content": [{"type": "text", "text": text}]})
    write("system", subtype="turn_duration", durationMs=int((time.time() - started) * 1000))
    stand_in.report("idle")
    say(text)


def play(text, turn):
    """A scripted turn of the welcome pictures, dated as if it took `secs`: ends idle, or works on in its last tool."""
    at = time.time() - turn["secs"]
    write("user", at=at, message={"content": text})
    stand_in.report("working")
    for step in turn["steps"]:
        started, at = at, at + step.get("secs", 2)
        if "text" in step:
            write("assistant", at=at, effort="high", message={"model": turn["model"], "content": [
                {"type": "text", "text": step["text"]}]})
            continue
        tool_id = "toolu_" + uuid.uuid4().hex[:24]
        write("assistant", at=started, effort="high", message={"model": turn["model"], "content": [
            {"type": "tool_use", "id": tool_id, "name": step["tool"], "input": step["input"]}]})
        if "output" in step:
            write("user", at=at, toolUseResult=step.get("result"), message={"content": [
                {"type": "tool_result", "tool_use_id": tool_id, "content": step["output"]}]})
    if turn.get("working"):
        return
    write("system", at=at, subtype="turn_duration", durationMs=turn["secs"] * 1000)
    stand_in.report("idle")


def prompt(text, started):
    if text in scene:
        return play(text, scene[text])
    write("user", message={"content": text})
    stand_in.report("working")
    if text == "wait":
        stand_in.report("blocked")
        say("Allow this command?\n  1. Yes\n  2. No")
        while "1" not in key():
            pass
        stand_in.report("working")
        reply("Allowed.", started)
    elif text == "ask":
        questions = [{"question": "Which fruit?", "header": "Fruit", "multiSelect": False,
                      "options": [{"label": "Apple", "description": ""}, {"label": "Pear", "description": ""}]}]
        stand_in.report("blocked")
        say("Which fruit? 1. Apple 2. Pear")
        decision = hook("PermissionRequest", {"session_id": token, "hook_event_name": "PermissionRequest",
                                              "tool_name": "AskUserQuestion", "tool_input": {"questions": questions}})
        answers = json.loads(decision)["hookSpecificOutput"]["decision"]["updatedInput"]["answers"]
        stand_in.report("working")
        reply("You chose " + answers["Which fruit?"] + ".", started)
    elif text == "slow":
        tool("sleep 30", None)
        deadline = time.time() + 30
        while time.time() < deadline and "\x1b" not in key(deadline - time.time()):
            pass
        write("user", message={"content": "[Request interrupted by user]"})
        stand_in.report("idle")
        say("Interrupted")
    elif text == "steps":
        for said, commands in [("First, a look.", ["ls"]), ("Then two more.", ["pwd", "date"])]:
            write("assistant", message={"model": "claude-stand-in", "content": [{"type": "text", "text": said}]})
            for command in commands:
                tool(command, command)
        reply("Done.", started)
    elif text == "long":
        tool("seq 200", "\n".join(str(n) for n in range(1, 201)))
        reply("Counted.", started)
    elif text.split()[0] == "many":
        words = text.split()
        turns, more = int((words + ["150"])[1]), int((words + ["0", "0"])[2])
        for turn in range(1, turns + 1):
            write("user", message={"content": f"Question {turn}"})
            tool(f"echo {turn}", str(turn))
            paragraphs = [f"Paragraph {k} of reply {turn}, long enough to wrap in a narrow card. " * (1 + turn % 3)
                          for k in range(1 + turn % 2 + more)]
            write("assistant", message={"model": "claude-stand-in", "content": [
                {"type": "text", "text": f"Reply {turn}.\n\n" + "\n\n".join(paragraphs)}]})
            write("system", subtype="turn_duration", durationMs=1000)
        reply("Last.", started)
    elif text == "big":
        for _ in range(40):
            write("api-request-blob", blob="x" * 8192)
        reply("Big.", started)
    else:
        time.sleep(0.5)
        tool("echo " + text, text)
        reply("Echo: **" + text + "**", started)


def cleanup():
    if "--settings" in args and os.path.exists(transcript):
        os.remove(transcript)
    for side in re.findall(r"/\.cache/ovvi/chat/([0-9a-f-]{36})", settings)[:1]:
        shutil.rmtree(os.path.expanduser("~/.cache/ovvi/chat/" + side), ignore_errors=True)
    # Bracketed paste off again, as Claude Code leaves it: bash 3.2 would take herdr's next paste marks as text.
    try:
        sys.stdout.write("\x1b[?2004l")
        sys.stdout.flush()
    except OSError:
        pass


def main():
    hook("SessionStart", {"session_id": token, "transcript_path": transcript, "cwd": os.getcwd(),
                          "hook_event_name": "SessionStart", "source": "resume" if resumed else "startup"})
    with terminal(cleanup):
        loop()


def loop():
    say("Claude Code stand-in " + token)
    stand_in.report("idle")
    # Started by hand, as herdr's integration would: herdr takes a session once the pane has its agent, and takes no
    # state report after it (so not with the flags, whose tests need the states).
    if "--settings" not in args:
        herdr("report-agent-session", "--source", "herdr:claude", "--agent", "claude", "--agent-session-id", token)
    line, mute, armed = "", False, False
    while True:
        data = key()
        if "\x03" in data:
            if not line and armed:
                break
            armed, line = not line, ""
            say("\r\x1b[KPress Ctrl-C again to exit" if armed else "")
            continue
        if "\x04" in data:
            break
        armed = False
        line += data.replace("\x1b", "")
        if "\r" not in line:
            sys.stdout.write(data.replace("\x1b", ""))
            sys.stdout.flush()
            continue
        text, line = line.split("\r", 1)
        say("")
        if text.strip() == "/exit":
            time.sleep(float(os.environ.get("OVVI_STAND_IN_EXIT_HOOKS", "0")))
            break
        if mute:
            mute = False
        elif text.strip():
            prompt(text.strip(), time.time())
            mute = text.strip() == "mute"


main()
