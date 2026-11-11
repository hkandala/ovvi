// The welcome clips' custom plugin: the latest deploys of the card's project, made up (scripts/record-onboarding.sh).
import type { Ovvi } from "@ovvi/plugin-api"
import "./main.css"

const deploys = [
  ["building", "Add dark mode", "now"],
  ["live", "Rate limit /links", "12 min"],
  ["live", "Tidy the styles", "1 h"],
  ["live", "First version", "3 h"],
]

export default async function main(ovvi: Ovvi) {
  ovvi.controls.set("site", { value: "shortlink.example.com" })
  const list = document.body.appendChild(document.createElement("ul"))
  for (const [state, title, when] of deploys) {
    const row = list.appendChild(document.createElement("li"))
    row.className = state
    for (const [name, text] of [["dot", ""], ["title", title], ["state", state === "live" ? "Live" : "Building"],
                                ["when", when]]) {
      row.appendChild(document.createElement("span")).className = name
      row.lastElementChild!.textContent = text
    }
  }
}
