// The screen bridge: joins the Tart VM card's WebSocket to a VM's Screen Sharing (VNC, TCP port 5900). A web page
// cannot open a TCP socket; the card's manifest lets its page reach this one origin (`connect`).
import { execFile } from "node:child_process"
import net from "node:net"
import { promisify } from "node:util"
import { WebSocketServer } from "ws"

const run = promisify(execFile)
const port = 57900
const path = /^\/vm\/([A-Za-z0-9][A-Za-z0-9._-]*)\/(rfb|lock)$/

// Any web page on this Mac can aim at 127.0.0.1, and WebSockets have no CORS: only the card's own page gets a screen.
// A browser sets Origin itself, and a DNS rebinding sends another Host.
const ours = ({ req }) =>
  req.headers.host === `127.0.0.1:${port}` && req.headers.origin === "ovvi-plugin://tart-vm" && path.test(req.url)

/** The VM's owner while a tool holds its "in use" lock (README, In use), "" with no owner named, else null. */
const inUse = (vm) =>
  run(new URL("bin/ovvi-tart", import.meta.url).pathname, ["in-use", vm]).then((r) => r.stdout.trim(), () => null)

new WebSocketServer({ host: "127.0.0.1", port, verifyClient: ours }).on("connection", async (ws, req) => {
  // With no listener, a bad frame would end the bridge, and every open screen with it.
  ws.on("error", () => ws.terminate())
  const [, vm, what] = req.url.match(path)
  if (what === "lock") {
    // The card sends the VM no input while it is in use: it hears the owner (JSON), and null when it frees.
    let sent
    const tick = async () => {
      const owner = JSON.stringify(await inUse(vm))
      if (owner !== sent && ws.readyState === ws.OPEN) ws.send((sent = owner))
    }
    const timer = setInterval(tick, 1000)
    ws.on("close", () => clearInterval(timer))
    return tick()
  }
  let ip
  try {
    ip = (await run("tart", ["ip", vm])).stdout.trim()
  } catch {
    return ws.close()
  }
  if (ws.readyState !== ws.OPEN) return
  const vnc = net.connect(5900, ip)
  vnc.on("data", (data) => ws.send(data))
  ws.on("message", (data) => vnc.write(data))
  vnc.on("close", () => ws.close())
  vnc.on("error", () => ws.close())
  ws.on("close", () => vnc.destroy())
})
