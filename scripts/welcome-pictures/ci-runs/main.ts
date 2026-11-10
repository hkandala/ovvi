// CI Runs: a ci.json file's runs, newest first, each with its state, branch and time.
import type { Ovvi } from "@ovvi/plugin-api"
import "./main.css"

type Run = { name: string; branch: string; commit: string; state: "running" | "passed" | "failed"; when: string }

export default async function main(ovvi: Ovvi) {
  const list = document.body.appendChild(document.createElement("ul"))
  async function load() {
    const { text } = await ovvi.files.read(ovvi.card.arg)
    const runs = JSON.parse(text) as Run[]
    const failing = runs.filter((run) => run.state === "failed").length
    ovvi.controls.set("summary", { value: `${runs.length} runs · ${failing} failing` })
    list.replaceChildren(...runs.map((run) => {
      const row = document.createElement("li")
      const mark = row.appendChild(document.createElement("span"))
      mark.className = `mark ${run.state}`
      mark.textContent = run.state === "passed" ? "✓" : run.state === "failed" ? "✕" : ""
      const words = row.appendChild(document.createElement("div"))
      words.appendChild(document.createElement("b")).textContent = run.name
      words.appendChild(document.createElement("small")).textContent = `${run.branch} · ${run.commit}`
      row.appendChild(document.createElement("time")).textContent = run.when
      return row
    }))
  }
  ovvi.files.watch(ovvi.card.arg, load)
  await load()
}
