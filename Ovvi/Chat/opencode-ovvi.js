import { appendFileSync } from "node:fs"
export default {
  id: "ovvi.state",
  tui: async (api) => {
    const file = process.env.OVVI_OC_STATE
    if (!file) return
    let last = ""
    const tick = () => {
      const route = api.route.current
      // The server's address comes from the SDK client's protected `client`: check it on each opencode release.
      const config = api.client?.client?.getConfig?.()
      const line = JSON.stringify({ pid: process.pid, url: config?.baseUrl ?? null,
        session: route?.name === "session" ? route.params?.sessionID ?? null : null, dialog: api.ui.dialog.open })
      // A plugin must never break its host: a removed folder only ends the reports.
      if (line !== last) { last = line; try { appendFileSync(file, line + "\n") } catch {} }
    }
    tick()
    const timer = setInterval(tick, 200)
    api.lifecycle.onDispose(() => clearInterval(timer))
  },
}
