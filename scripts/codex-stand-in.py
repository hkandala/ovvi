#!/usr/bin/env python3
"""Codex's stand-in for the chat view's UI tests (CI has no Codex).

Started by the chooser with Ovvi's flags (`-c hooks.SessionStart=… -c hooks.state=…`), it checks the hook's trust
hash as Codex does (else it shows Codex's "Hooks need review" picker and runs no hook), runs the hook at the first
prompt, writes a rollout in Codex's format under $CODEX_HOME/sessions (else under its own folder), reports its state to
herdr and draws Codex's input box above its status row. Started without flags it reports its session to herdr at the
first prompt (as herdr's Codex integration does) and keeps its rollout, which `resume <session>` goes on with.
Prompts: "wait" shows an approval until 1 is typed, "model" opens a picker (herdr still says idle) until Esc, "slow"
works until Esc, "new" starts a new session (as `/new` and a prompt do), a prompt of OVVI_STAND_IN_SCENE's
turns plays that turn (scripts/welcome-scene/scene.py), anything else gets one command and the reply "Echo: <prompt>".
"""
import hashlib
import json
import os
import re
import shutil
import subprocess
import time
import uuid
from glob import glob

import stand_in
from stand_in import folder, key, say, terminal

args = stand_in.run_as("codex", __file__)
values = [args[i + 1] for i, arg in enumerate(args[:-1]) if arg == "-c"]
hook = next((re.search(r'command="([^"]*)"', v).group(1) for v in values if v.startswith("hooks.SessionStart=")), None)
trusted = next((re.search(r'trusted_hash="([^"]*)"', v).group(1) for v in values if v.startswith("hooks.state=")), "")
# Codex's hash of a hook: sha256 of its sorted compact JSON, with the defaults filled in.
identity = {"event_name": "session_start",
            "hooks": [{"async": False, "command": hook, "timeout": 600, "type": "command"}]}
trusts = not hook or trusted == "sha256:" + hashlib.sha256(json.dumps(identity, sort_keys=True, separators=(",", ":"))
                                                           .encode()).hexdigest()
token = re.search(r"/\.cache/ovvi/chat/([0-9a-f-]{36})/", hook).group(1) if hook else None
home = os.environ.get("CODEX_HOME") or os.path.join(folder, "codex")
thread = args[args.index("resume") + 1] if "resume" in args[:-1] else None
# The resumed session's rollout, which Codex appends to; `made` are the new ones.
rollouts = glob(os.path.join(home, "sessions/*/*/*/rollout-*-" + thread + ".jsonl"))[:1] if thread else []
made = []
started = False
scene = json.load(open(os.environ["OVVI_STAND_IN_SCENE"]))["codex"] if os.environ.get("OVVI_STAND_IN_SCENE") else {}


def write(kind, at=None, **payload):
    line = {"timestamp": time.strftime("%Y-%m-%dT%H:%M:%S.000Z", time.gmtime(at)), "type": kind, "payload": payload}
    with open(rollouts[-1], "a") as file:
        file.write(json.dumps(line) + "\n")


def item(kind, at=None, **fields):
    write("event_msg", at=at, type="item_completed", item={"type": kind, "id": str(uuid.uuid4()), **fields})


def play(text, turn):
    """A scripted turn of the welcome pictures, dated as if it took `secs`: ends idle, or works on."""
    at, turn_id = time.time() - turn["secs"], str(uuid.uuid4())
    write("event_msg", at=at, type="task_started", turn_id=turn_id)
    write("turn_context", at=at, turn_id=turn_id, cwd=os.getcwd(), model=turn["model"], effort="high")
    item("UserMessage", at=at, content=[{"type": "text", "text": text}])
    stand_in.report("working")
    for step in turn["steps"]:
        at += step.get("secs", 2)
        item(step["type"], at=at, **{key: value for key, value in step.items() if key not in ("type", "secs")})
    if not turn.get("working"):
        write("event_msg", at=at, type="task_complete", turn_id=turn_id, duration_ms=turn["secs"] * 1000)
        stand_in.report("idle")


def box():
    say("\n› Ask Codex to do anything\n\n  stand-in high · " + os.getcwd() + "\n  ? for shortcuts")


def start(new):
    """Codex starts its session at the first prompt (a resumed one too), and a hidden thread with no rollout."""
    global thread, started
    if new:
        thread = str(uuid.uuid4())
        day = time.strftime("%Y/%m/%d")
        rollouts.append(os.path.join(home, "sessions", day, "rollout-" + time.strftime("%Y-%m-%dT%H-%M-%S-") + thread
                                     + ".jsonl"))
        made.append(rollouts[-1])
        os.makedirs(os.path.dirname(rollouts[-1]), exist_ok=True)
        write("session_meta", id=thread, source="cli", cli_version="0.163.0", cwd=os.getcwd())
    started = True
    if not hook:
        stand_in.herdr("report-agent-session", "--source", "herdr:codex", "--agent", "codex", "--agent-session-id",
                       thread)
        return
    for path in [rollouts[-1], None]:
        subprocess.run([os.environ.get("SHELL", "/bin/sh"), "-lc", hook], capture_output=True, input=json.dumps(
            {"session_id": thread, "transcript_path": path, "cwd": os.getcwd(), "hook_event_name": "SessionStart",
             "model": "stand-in", "source": "startup" if new else "resume"}), text=True)


def prompt(text, started_at):
    if not started or text == "new":
        start(text == "new" or not rollouts)
    if text in scene:
        return play(text, scene[text])
    turn = str(uuid.uuid4())
    write("event_msg", type="task_started", turn_id=turn)
    write("turn_context", turn_id=turn, cwd=os.getcwd(), model="codex-stand-in", effort="high")
    item("UserMessage", content=[{"type": "text", "text": text}])
    stand_in.report("working")
    if text == "wait":
        stand_in.report("blocked")
        say("  Would you like to run the following command?\n› 1. Yes, proceed (y)\n  2. No (esc)\n"
            "  Press enter to confirm or esc to cancel")
        while "1" not in key():
            pass
        stand_in.report("working")
        item("AgentMessage", content=[{"type": "Text", "text": "Allowed."}], phase="final_answer")
    elif text == "model":
        stand_in.report("idle")
        say("  Select Model and Effort\n› 1. stand-in (current)\n  2. other\n  enter select · esc back")
        while "\x1b" not in key():
            pass
        box()
        return
    elif text == "slow":
        box()
        deadline = time.time() + 30
        while time.time() < deadline and "\x1b" not in key(deadline - time.time()):
            pass
        write("event_msg", type="turn_aborted", turn_id=turn, reason="interrupted")
        stand_in.report("idle")
        say("■ Conversation interrupted")
        box()
        return
    else:
        time.sleep(0.5)
        item("CommandExecution", command=["/bin/zsh", "-lc", "echo " + text], parsed_cmd=[], status="completed",
             aggregated_output=text + "\n", exit_code=0, duration={"secs": 0, "nanos": 1000})
        item("AgentMessage", content=[{"type": "Text", "text": "Echo: **" + text + "**"}], phase="final_answer")
    write("event_msg", type="task_complete", turn_id=turn, duration_ms=int((time.time() - started_at) * 1000))
    stand_in.report("idle")
    say("• done")
    box()


def cleanup():
    if hook:
        for rollout in made:
            os.remove(rollout)
        shutil.rmtree(os.path.expanduser("~/.cache/ovvi/chat/" + token), ignore_errors=True)


def main():
    with terminal(cleanup):
        say("Codex stand-in " + str(token))
        if not trusts:
            say("  Hooks need review\n› 1. Review hooks\n  2. Trust all\n  enter select · esc back")
        else:
            box()
        stand_in.report("idle")
        line = ""
        while True:
            data = key()
            if "\x03" in data or "\x04" in data:
                break
            line += data.replace("\x1b", "")
            if "\r" not in line:
                continue
            text, line = line.split("\r", 1)
            if trusts and text.strip():
                prompt(text.strip(), time.time())


main()
