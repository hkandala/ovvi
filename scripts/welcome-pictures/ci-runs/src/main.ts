// CI Runs, the welcome pictures' custom plugin: a project's runs from its ci.json, the newest first, each with its
// state.
import type { Ovvi } from "@ovvi/plugin-api"
import "./main.css"

type Run = { name: string; branch: string; commit?: string; state: "running" | "passed" | "failed"; when: string }

export default async function main(ovvi: Ovvi) {
  const list = document.body.appendChild(document.createElement("ul"))
  async function load() {
    const runs: Run[] = JSON.parse((await ovvi.files.read(ovvi.card.arg)).text)
    const failing = runs.filter((run) => run.state === "failed").length
    ovvi.controls.set("count", { value: `${runs.length} runs · ${failing} failing` })
    list.replaceChildren(...runs.map((run) => {
      const row = document.createElement("li")
      row.className = run.state
      row.appendChild(document.createElement("i")).textContent =
        run.state === "passed" ? "✓" : run.state === "failed" ? "✕" : ""
      const text = row.appendChild(document.createElement("div"))
      text.appendChild(document.createElement("b")).textContent = run.name
      text.appendChild(document.createElement("span")).textContent = [run.branch, run.commit].filter(Boolean).join(" · ")
      row.appendChild(document.createElement("time")).textContent = run.when
      return row
    }))
  }
  ovvi.files.watch(ovvi.card.arg, load)
  await load()
}
