#!/usr/bin/env python3
"""pi's stand-in for the chat view's UI tests (CI has no pi).

Started by the chooser with Ovvi's flags (`-e <pi-ovvi-<sha8>.ts> --ovvi <state file>`), it needs the extension
file whole (its sha256 starts with the name's sha8), writes the state lines pi-ovvi writes and a session file in pi's
format, reports its state to herdr and answers prompts on its terminal: "wait" opens a dialog until 1 is typed, "slow"
works until Esc and takes a message sent meanwhile after its tool, as pi steers, "/tree" moves the leaf back before
the last user message, "tools" runs every kind of tool, "agents" ends its turn while herdr hears working until 1 is
typed, a prompt of OVVI_STAND_IN_SCENE's turns plays that turn (scripts/welcome-scene/scene.py), anything else gets one
command and the reply "Echo: <prompt>".
"""
import hashlib
import json
import os
import shutil
import sys
import time
import uuid

import stand_in
from stand_in import folder, key, say, terminal

args = stand_in.run_as("pi", __file__)
extension, state = args[args.index("-e") + 1], args[args.index("--ovvi") + 1]
if not os.path.isfile(extension):
    sys.exit("Failed to load extension: Extension path does not exist: " + extension)
with open(extension, "rb") as file:
    if not os.path.basename(extension).endswith("-" + hashlib.sha256(file.read()).hexdigest()[:8] + ".ts"):
        sys.exit("The extension is not whole: " + extension)
os.makedirs(os.path.dirname(state), mode=0o700, exist_ok=True)
transcript = os.path.join(folder, os.path.basename(os.path.dirname(state)) + ".jsonl")
leaf = None
scene = json.load(open(os.environ["OVVI_STAND_IN_SCENE"]))["pi"] if os.environ.get("OVVI_STAND_IN_SCENE") else {}


def line(path, value):
    with open(path, "a") as file:
        file.write(json.dumps(value) + "\n")


def entry(role, at=None, **fields):
    """Appends a message entry to the leaf, as pi does."""
    global leaf
    entry_id = uuid.uuid4().hex[:8]
    line(transcript, {"type": "message", "id": entry_id, "parentId": leaf,
                      "timestamp": time.strftime("%Y-%m-%dT%H:%M:%S.000Z", time.gmtime(at)),
                      "message": {"role": role, "timestamp": int((at or time.time()) * 1000), **fields}})
    leaf = entry_id
    return entry_id


def assistant(content, stop, model="pi-stand-in", **fields):
    entry("assistant", content=content, api="stand-in", provider="stand-in", model=model, stopReason=stop, **fields)


def play(text, turn):
    """A scripted turn of the welcome pictures, dated as if it took `secs`: ends idle, or works on in its last tool."""
    at = time.time() - turn["secs"]
    entry("user", at=at, content=[{"type": "text", "text": text}])
    line(state, {"type": "working"})
    stand_in.report("working")
    for step in turn["steps"]:
        started, at = at, at + step.get("secs", 2)
        if "text" in step:
            assistant([{"type": "text", "text": step["text"]}], "stop", model=turn["model"], at=at)
            continue
        call = "toolu_" + uuid.uuid4().hex[:12]
        assistant([{"type": "toolCall", "id": call, "name": step["tool"], "arguments": step["arguments"]}], "toolUse",
                  model=turn["model"], at=started)
        if "output" in step:
            entry("toolResult", at=at, toolCallId=call, toolName=step["tool"],
                  content=[{"type": "text", "text": step["output"]}], details=step.get("details", {}), isError=False)
    if not turn.get("working"):
        line(state, {"type": "idle"})
        stand_in.report("idle")


def prompt(text):
    if text in scene:
        return play(text, scene[text])
    if text == "/tree":
        entries = {}
        with open(transcript) as file:
            for row in file:
                value = json.loads(row)
                entries[value.get("id")] = value
        global leaf
        node = entries.get(leaf)
        while node and node.get("message", {}).get("role") != "user":
            node = entries.get(node.get("parentId"))
        if node:
            leaf = node.get("parentId")
            line(state, {"type": "tree", "leaf": leaf, "at": os.path.getsize(transcript)})
        say("Navigated to selected point")
        return
    entry("user", content=[{"type": "text", "text": text}])
    line(state, {"type": "working"})
    stand_in.report("working")
    if text == "wait":
        line(state, {"type": "blocked"})
        stand_in.report("blocked")
        say("Allow this command?\n  1. Yes\n  2. No")
        while "1" not in key():
            pass
        line(state, {"type": "unblocked"})
        stand_in.report("working")
        assistant([{"type": "text", "text": "Allowed."}], "stop")
    elif text == "tools":
        tools()
    elif text == "agents":
        # pi-herd's wait on agents: the turn ends (idle in the state file) while herdr hears working, until 1 is typed.
        assistant([{"type": "text", "text": "Waiting on agents."}], "stop")
        say("Waiting on agents.")
        line(state, {"type": "idle"})
        while "1" not in key():
            pass
    elif text == "slow":
        call = "toolu_" + uuid.uuid4().hex[:12]
        assistant([{"type": "toolCall", "id": call, "name": "bash", "arguments": {"command": "sleep 30"}}], "toolUse")
        deadline, typed = time.time() + 30, ""
        while time.time() < deadline:
            data = key(deadline - time.time())
            if "\x1b" in data:
                break
            typed += data
        entry("toolResult", toolCallId=call, toolName="bash", content=[{"type": "text", "text": "Killed: 9"}],
              isError=True)
        for steer in typed.split("\r")[:-1]:
            entry("user", content=[{"type": "text", "text": steer.strip()}])
        assistant([], "error", errorMessage="The operation was aborted.")
        say("Interrupted")
    else:
        time.sleep(0.5)
        call = "toolu_" + uuid.uuid4().hex[:12]
        assistant([{"type": "toolCall", "id": call, "name": "bash", "arguments": {"command": "echo " + text}}],
                  "toolUse")
        entry("toolResult", toolCallId=call, toolName="bash", content=[{"type": "text", "text": text}], isError=False)
        assistant([{"type": "text", "text": "Echo: **" + text + "**"}], "stop")
        say("Echo: **" + text + "**")
    line(state, {"type": "idle"})
    stand_in.report("idle")


def tools():
    calls = [("read", {"path": os.path.join(os.getcwd(), "a.txt")}, {}),
             ("write", {"path": "b.txt", "content": "x\ny\n"}, {}),
             ("edit", {"path": "b.txt", "edits": [{"oldText": "x", "newText": "z"}]},
              {"diff": "- 1 x\n+ 1 z\n  2 y"}),
             ("grep", {"pattern": "needle"}, {}), ("find", {"pattern": "*.txt"}, {}), ("ls", {"path": "."}, {}),
             ("bash", {"command": "echo hi"}, {}),
             ("codemode", {"code": "await tools.read({path: 'c.txt'})"},
              {"calls": [{"id": "c/1", "name": "read", "args": '{"path":"c.txt"}', "status": "ok", "durationMs": 9}]}),
             ("agent_start", {"name": "helper", "message": {"text": "hi"}}, {})]
    assistant([{"type": "thinking", "thinking": "Plan.", "thinkingSignature": "x"}], "stop")
    for name, arguments, details in calls:
        call = "toolu_" + uuid.uuid4().hex[:12]
        assistant([{"type": "toolCall", "id": call, "name": name, "arguments": arguments}], "toolUse")
        entry("toolResult", toolCallId=call, toolName=name, content=[{"type": "text", "text": "ok"}],
              details=details, isError=False)
    assistant([{"type": "text", "text": "All tools."}], "stop")
    say("All tools.")


def cleanup():
    line(state, {"type": "shutdown"})
    if os.path.exists(transcript):
        os.remove(transcript)
    shutil.rmtree(os.path.dirname(state), ignore_errors=True)


def main():
    line(transcript, {"type": "session", "version": 3, "id": str(uuid.uuid4()),
                      "timestamp": time.strftime("%Y-%m-%dT%H:%M:%S.000Z", time.gmtime()), "cwd": os.getcwd()})
    line(state, {"type": "session", "path": transcript})
    with terminal(cleanup):
        say("pi stand-in " + state)
        stand_in.report("idle")
        text = ""
        while True:
            data = key()
            if "\x03" in data or "\x04" in data:
                break
            text += data.replace("\x1b", "")
            if "\r" not in text:
                sys.stdout.write(data.replace("\x1b", ""))
                sys.stdout.flush()
                continue
            text, rest = text.split("\r", 1)
            say("")
            if text.strip():
                prompt(text.strip())
            text = rest


main()
