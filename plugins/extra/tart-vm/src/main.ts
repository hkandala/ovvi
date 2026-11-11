// The Tart VM card: a list of this Mac's VMs, and a VM's screen in the card. The screen is the guest's Screen Sharing
// (VNC), drawn by noVNC through the bridge's WebSocket (bridge.mjs): Ovvi lets this page reach it (manifest `connect`).
import type { Ovvi } from "@ovvi/plugin-api"
import RFB from "@novnc/novnc"
import "./main.css"

declare const PLUGIN_DIR: string
const cli = `${PLUGIN_DIR}/bin/ovvi-tart`

interface VM { Name: string; State: string; Running: boolean; Size: number; Memory: number; CPU: number; os: string }
interface Info { os: string; CPU: number; Memory: number }

/** Cirrus Labs' base image, the first choice to copy: it stays clean, so it is never started, stopped or deleted here. */
const BASE = "golden-gate"
const valid = /^[A-Za-z0-9][A-Za-z0-9._-]*$/

const gb = (mb: number) => `${Math.round(mb / 1024)} GB`
function el<K extends keyof HTMLElementTagNameMap>(tag: K, props: Partial<HTMLElementTagNameMap[K]> = {}) {
  return Object.assign(document.createElement(tag), props) as HTMLElementTagNameMap[K]
}

export default async function main(ovvi: Ovvi) {
  const screen = document.body.appendChild(el("div", { id: "screen" }))
  const notice = document.body.appendChild(el("main"))
  // The user and password of Cirrus Labs' images; a VM with others asks once, for this card.
  let credentials = { username: "admin", password: "admin" }
  let rfb: RFB | undefined
  let lock: WebSocket | undefined
  let shown = ""

  async function tart(args: string[], timeout = 30_000) {
    const r = await ovvi.run([cli, ...args], { timeout })
    if (r.code !== 0) throw new Error(r.stderr.trim() || `ovvi-tart ${args[0]} failed`)
    return r.stdout.trim()
  }

  type Button = [string, () => void, boolean?]
  const buttons = (list: Button[]) => {
    const row = el("div")
    for (const [text, action, main] of list) {
      row.appendChild(el("button", { textContent: text, type: "button", className: main ? "main" : "", onclick: action }))
    }
    return row
  }

  function draw(title: string, detail: string, list: Button[] = [], ...more: Node[]) {
    notice.replaceChildren(el("h2", { textContent: title }), el("p", { textContent: detail }), ...more, buttons(list))
    notice.hidden = false
  }

  /** The VM's facts in row 2; Back and Open in Tart only on a VM's page. */
  function header(info?: string, running = false) {
    ovvi.controls.set("back", { hidden: !shown })
    ovvi.controls.set("info", { value: info ?? "", hidden: info === undefined })
    ovvi.controls.set("tart", { hidden: !running })
  }

  /** Ends the shown screen's connection (the VM runs on); its disconnect event then finds it is not the current one. */
  function drop() {
    const r = rfb
    rfb = undefined
    r?.disconnect()
    lock?.close()
    lock = undefined
    ovvi.controls.set("in-use", { hidden: true })
    screen.replaceChildren()
  }

  ovvi.on("control", async ({ id }) => {
    const vm = shown
    if (id === "back") return void home()
    if (id !== "tart" || !vm) return
    const pick = await ovvi.toast(`Open ${vm} in Tart? It pauses for a few seconds and comes back as it was.`, ["Cancel", "Open in Tart"])
    if (pick !== "Open in Tart") return
    drop()
    header("Moving to Tart")
    draw(`Opening ${vm} in Tart…`, "Tart saves the VM and opens it in its own window.")
    // A refusal (the VM is in use) leaves it running: the card connects again either way.
    await tart(["window", vm], 180_000).catch((error) => void ovvi.toast(`${vm} did not open in Tart: ${(error as Error).message}`))
    if (shown === vm) await show(vm, true)
  })

  /** Shows a VM's screen; a VM that is off starts first, with no window. */
  async function show(vm: string, running = false) {
    shown = vm
    document.title = vm
    drop()
    header(running ? "Running" : "Starting")
    if (running) draw(`Connecting to ${vm}…`, "")
    else draw(`Starting ${vm}…`, "A VM takes about half a minute to boot.")
    let info: Info
    try {
      info = JSON.parse(await tart(["view", vm], 180_000))
    } catch (error) {
      if (shown !== vm) return
      header()
      return draw(`${vm} did not start`, (error as Error).message, [["All VMs", () => void home()], ["Try Again", () => void show(vm), true]])
    }
    if (shown !== vm) return
    header(["Running", info.os && `macOS ${info.os}`, `${info.CPU} cores`, gb(info.Memory)].filter(Boolean).join(" · "), true)
    connect(vm)
  }

  function connect(vm: string) {
    draw(`Connecting to ${vm}…`, "")
    drop()
    const r = (rfb = new RFB(screen, `ws://127.0.0.1:57900/vm/${encodeURIComponent(vm)}/rfb`, { credentials }))
    r.scaleViewport = true
    r.background = "transparent"
    // A pointer move or a key would break what a tool that holds the VM's lock does (a test run): no input while
    // one holds it, nor until the bridge has said whether one does.
    r.viewOnly = true
    lock = new WebSocket(`ws://127.0.0.1:57900/vm/${encodeURIComponent(vm)}/lock`)
    lock.onmessage = ({ data }) => {
      const owner = JSON.parse(data) as string | null
      r.viewOnly = owner !== null
      ovvi.controls.set("tart", { enabled: owner === null })
      ovvi.controls.set("in-use", { value: owner ? `In use · ${owner}` : "In use", hidden: owner === null })
    }
    let refused = false
    // No focus() here: a page that focuses takes the keyboard from the focused card; a click on the screen gives it.
    r.addEventListener("connect", () => (notice.hidden = true))
    r.addEventListener("securityfailure", () => (refused = true))
    r.addEventListener("credentialsrequired", () => signIn(vm, (c) => r.sendCredentials(c)))
    r.addEventListener("disconnect", () => {
      if (rfb !== r) return
      rfb = undefined
      if (refused) return signIn(vm, () => connect(vm))
      header("Not connected")
      draw(`${vm} is not connected`, "It stopped, or its Screen Sharing went away.", [
        ["All VMs", () => void home()],
        ["Connect Again", () => void show(vm), true],
      ])
    })
  }

  function signIn(vm: string, then: (c: typeof credentials) => void) {
    const form = el("form")
    for (const [name, type, placeholder] of [["username", "text", "User"], ["password", "password", "Password"]]) {
      form.appendChild(el("input", { name, type, placeholder }))
    }
    form.appendChild(el("button", { textContent: "Connect", className: "main" }))
    form.onsubmit = (e) => {
      e.preventDefault()
      const data = new FormData(form)
      credentials = { username: String(data.get("username")), password: String(data.get("password")) }
      draw(`Connecting to ${vm}…`, "")
      then(credentials)
    }
    draw(`Sign in to ${vm}`, "Its Screen Sharing asks for a user of the VM.", [], form)
  }

  async function stop(vm: string) {
    const pick = await ovvi.toast(`Stop ${vm}? It shuts down: what is not saved in it is lost.`, ["Cancel", "Stop"],
      { destructive: true })
    if (pick !== "Stop") return
    draw(`Stopping ${vm}…`, "")
    await tart(["stop", vm], 90_000).catch((error) => void ovvi.toast(`${vm} did not stop: ${(error as Error).message}`))
    await home(true)
  }

  async function remove(v: VM) {
    const pick = await ovvi.toast(`Delete ${v.Name}? Its ${v.Size} GB disk goes with it. This cannot be undone.`,
      ["Cancel", "Delete"], { destructive: true })
    if (pick !== "Delete") return
    draw(`Deleting ${v.Name}…`, "")
    await tart(["delete", v.Name], 90_000)
      .catch((error) => void ovvi.toast(`${v.Name} was not deleted: ${(error as Error).message}`))
    await home(true)
  }

  function create(vms: VM[], hostMemory: number) {
    const up = vms.filter((v) => v.Running)
    // A copy of a VM that is off; the base image first.
    const off = vms.filter((v) => !v.Running).sort((a, b) => Number(b.Name === BASE) - Number(a.Name === BASE))
    let n = 1
    while (vms.some((v) => v.Name === `vm-${n}`)) n++
    const back: Button = ["Cancel", () => void home()]
    if (!off.length) return draw("No VM to copy", "A new VM is a copy of a VM that is off: stop one first.", [back])
    const base = off[0]
    const cost = `A copy of ${base.Name} takes ${gb(base.Memory)} of memory and ${base.CPU} cores while it runs.`
    // macOS runs two VMs at most, and each holds its memory: a second one is worth a question.
    if (up.length > 1) return draw("Two VMs run already", `${cost} macOS runs two at most: stop one first.`, [back])
    const name = el("input", { name: "name", value: `vm-${n}`, placeholder: "Name", required: true, pattern: valid.source })
    const from = el("select", { name: "from", title: "A copy of" })
    for (const v of off) from.append(el("option", { value: v.Name, textContent: `a copy of ${v.Name}` }))
    const form = el("form")
    form.append(name, from)
    form.onsubmit = (e) => {
      e.preventDefault()
      if (vms.some((v) => v.Name === name.value)) return void ovvi.toast(`A VM named ${name.value} exists already.`)
      void make(name.value, from.value)
    }
    draw(
      "New VM",
      `${cost} ` +
        (up.length ? `${up[0].Name} runs already, with ${gb(up[0].Memory)} of this Mac's ${gb(hostMemory)}: ` +
          "a second VM runs beside it (macOS runs two at most)." : ""),
      [back, [up.length ? "Create and Start a Second VM" : "Create and Start", () => form.requestSubmit(), true]],
      form,
    )
    name.select()
  }

  async function make(name: string, from: string) {
    draw(`Creating ${name}…`, `A copy of ${from}: it shares the disk until it changes.`)
    try {
      await tart(["new", name, from], 120_000)
      // The kept list gets the new VM while it boots, so the list shows it on the way back.
      void fetchList().catch(() => {})
      await show(name)
    } catch (error) {
      draw(`${name} was not created`, (error as Error).message, [["All VMs", () => void home()]])
    }
  }

  /** `ovvi-tart list`'s last answer: this card's own (each pane runs its own page), kept while the page lives. */
  let kept: string | undefined
  let asked = 0

  /** Tart's list now; it is kept only while no newer one was asked for. */
  async function fetchList() {
    const n = ++asked
    const json = await tart(["list"])
    if (n === asked) kept = json
    return json
  }

  /** The card's home, this Mac's VMs: the kept list at once, then Tart's answer. `fresh` (after a change) waits for it. */
  async function home(fresh = false) {
    shown = ""
    drop()
    document.title = "All VMs"
    header()
    const old = kept
    if (!old) draw("Looking for VMs…", "")
    else if (!fresh) list(old)
    // Each draw makes a new title: another title means the user went on (a VM, New VM…), and the answer waits.
    const at = notice.firstChild
    let json: string
    try {
      json = await fetchList()
    } catch (error) {
      if (notice.firstChild === at) draw("Tart did not answer", (error as Error).message, [["Try Again", () => void home()]])
      return
    }
    if (notice.firstChild === at && (fresh || json !== old)) list(json)
  }

  function list(json: string) {
    const { vms, hostMemory }: { vms: VM[]; hostMemory: number } = JSON.parse(json)
    if (!vms.length) return draw("No VMs on this Mac", "Make one with `tart clone`, then try again.", [["Try Again", () => void home()]])
    const ul = el("ul")
    for (const v of vms) {
      const state = v.Name === BASE ? "Base for new VMs" : v.State[0].toUpperCase() + v.State.slice(1)
      const li = ul.appendChild(el("li"))
      const text = li.appendChild(el("div"))
      text.append(el("b", { textContent: v.Name }),
        el("span", { textContent: [state, v.os && `macOS ${v.os}`, `${v.CPU} cores`, gb(v.Memory)].filter(Boolean).join(" · ") }))
      if (v.Name === BASE) continue
      li.append(buttons([
        ...(v.Running ? [["Stop", () => void stop(v.Name)] as Button] : []),
        ...(v.State === "stopped" ? [["Delete", () => void remove(v)] as Button] : []),
        ["Open", () => void show(v.Name, v.Running), true],
      ]))
    }
    draw("Tart VMs", "", [["New VM…", () => create(vms, hostMemory)]], ul)
  }

  ovvi.card.ready()
  if (ovvi.card.machine.remote) draw("Tart VMs run on This Mac only", "")
  else await home()
}
