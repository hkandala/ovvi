# Tart VM, an Ovvi plugin

This Mac's [Tart](https://tart.run) VMs in an Ovvi card: start, stop, create and delete them, and a VM's screen in
the card, with its keyboard and pointer, scaled to the card.

- **New pane ▸ Tart VM** (or ⌘K "Open Tart VM Here") shows the list of VMs: each with its state, macOS version
  (once the card has seen it), cores and memory. "Looking for VMs…" shows on the card's first load only: back from a
  VM or New VM…, the card shows the list it has at once and updates it from Tart; each card has its own, in memory.
  **Open** shows a VM's screen in the card (a VM that is off starts first, with no window); **Stop** shuts a running
  VM down; **Delete**, on a stopped VM only (not a suspended one), deletes it with its disk. Stop and Delete ask
  first, with a red button. The base, `golden-gate` (Tart's stock macOS image), is never started, stopped or deleted
  here: **New VM…** makes a copy of it (or of another VM that is off), with a name, and says what it costs (its
  memory and cores; with a VM running, it asks for a second one; macOS runs two at most).
- A VM's page shows its screen and nothing else. The title is the VM's name; the header shows **‹** (back to the
  list), its state, macOS version, cores and memory, and **Open in Tart**. Back, or closing the card, only ends the
  screen's connection: the VM runs on until **Stop**.
- **Open in Tart** moves the same VM, with its state, into Tart's own window: Tart saves it (`tart suspend`) and
  restores it there, in about 8 seconds. Closing Tart's window suspends the VM; **Open** in the card resumes it.
- While a VM is in use (below), its card only watches: it sends no pointer or key to the VM, and the header shows
  "In use · ‹owner›". Input comes back when the lock frees. **Open in Tart**, **Stop** and **Delete** refuse then.
- macOS Screen Sharing sends no pointer shape and draws no pointer into a VM's screen: the card shows the system
  arrow over the screen.

## In use

A tool that uses a VM, and that a click, a pointer move or a suspend would break (a UI test run, a script that types
in the guest), marks the VM in use while it runs:

```sh
mkdir -p ~/.config/ovvi-tart/locks
echo "my-tests" > ~/.config/ovvi-tart/locks/<vm>.owner      # optional: the name the card shows
lockf -k ~/.config/ovvi-tart/locks/<vm>.lock <command>         # or flock(2) on that file
```

- The lock is the file's exclusive `flock` lock (what `lockf` holds), per VM. The kernel frees it when the holder
  ends, also when it is killed, so it never goes stale; `-k` keeps the file, so every holder locks the same one.
- The owner file is read only while the lock is held: a stale one is harmless.
- `ovvi-tart in-use <vm>` exits 0 and prints the owner while the lock is held. It reads the lock with `F_GETLK` and
  never takes it, so it never fails a holder's `lockf -t 0`. The bridge asks it every second for each open screen
  (`/vm/<vm>/lock`).

## Install

An extra plugin of Ovvi's repository: not in the app, installed from its folder, where it builds and loads.

```sh
cd ~/code/ovvi/plugins/extra/tart-vm && npm ci && npm run build
ovvi plugins install ~/code/ovvi/plugins/extra/tart-vm   # from a pane in Ovvi, or paste the path in Settings ▸ Plugins
ln -sfn ~/code/ovvi/plugins/extra/tart-vm/bin/ovvi-tart ~/.local/bin/ovvi-tart   # optional, for scripts
```

After a change to `bridge.mjs`, restart the bridge: `launchctl kickstart -k gui/$(id -u)/dev.ovvi.tart-bridge`.
The build keeps the folder's path (the card runs `bin/ovvi-tart` by it): after a move, build again. The bridge's
LaunchAgent keeps it too; a card's next screen replaces an agent made from another folder.

## How it works

```text
Tart VM card ── ovvi.run ──> bin/ovvi-tart list | new | view | window | stop | delete
     │                          view: starts the VM (tart run --no-graphics --suspendable) and the bridge
     │                          window: tart suspend, then tart run with Tart's window
     └── noVNC ── WebSocket ws://127.0.0.1:57900 ──> bridge.mjs (a LaunchAgent, dev.ovvi.tart-bridge)
                                                       ── TCP ──> the guest's Screen Sharing, <tart ip>:5900
```

- A Virtualization VM is drawn only by the process that runs it: Tart's window is a `VZVirtualMachineView` inside
  the `tart run` process, and Tart has no display API (its control socket only reaches the guest agent). So the card
  shows the guest's Screen Sharing (VNC, Apple's authentication, user and password `admin` on Tart's stock images),
  and **Open in Tart** hands the VM to a new `tart run` through a suspend and a resume. That needs VMs started with
  `--suspendable` (no audio and entropy devices, Mac input devices only); `ovvi-tart` starts them so.
- A web page cannot open a TCP socket, so the bridge joins the card's WebSocket to the guest. The manifest's
  `"connect": ["ws://127.0.0.1:57900"]` lets the card's page reach that one origin (Ovvi adds it to the page's
  Content Security Policy and names it when it asks to install the plugin).
- The bridge listens on 127.0.0.1 only and answers only the card: the Host must be `127.0.0.1:57900` and the Origin
  `ovvi-plugin://tart-vm`, which a browser sets itself, so another web page cannot reach a VM's screen.
- `ovvi-tart start <vm> --dir=…` keeps the `tart run` arguments for that VM in `~/.config/ovvi-tart/<vm>.args`:
  the card starts a VM the same way a script did.

## Limits

- The guest's screen keeps its size (Tart's `--display`, 1024 × 768 points by default): the card scales it.
- ⌘ keys that Ovvi uses (⌘T, ⌘W, ⌘K…) go to Ovvi, not to the VM. No clipboard sharing.
- Logs: `~/.config/ovvi-tart/<vm>.log` (tart run) and `~/Library/Logs/ovvi-tart-bridge.log`. Stop the bridge with
  `launchctl bootout gui/$(id -u)/dev.ovvi.tart-bridge`.
- A card on a remote machine says Tart VMs run on This Mac only.
