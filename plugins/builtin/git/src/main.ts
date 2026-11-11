import type { Ovvi } from "@ovvi/plugin-api"
import "./rows.css"
import "./home.css"
import "./diff.css"
import { ovvi as manifest } from "../package.json"
import * as Home from "./home"
import { bind, parse, sf } from "./lib"

const DIFF = manifest.header.flatMap(({ id }) => (id?.startsWith("diff.") ? [id] : []))
const HOME = manifest.header.flatMap(({ id }) => (id && !id.startsWith("diff.") ? [id] : []))

export default async function main(ovvi: Ovvi) {
  bind(ovvi)
  const big = ["checkmark.circle", "folder.badge.questionmark", "magnifyingglass"]
  const names = ["plus", "arrow.uturn.backward", "minus", "source.branch", "cloud", "tag", "xmark", ...big]
  const symbols = Promise.all(names.map((name) => ovvi.symbol(name, big.includes(name) ? 30 : 12).catch(() => "")))
  .then((urls) => {
    const sheet = document.createElement("style")
    sheet.textContent = `:root { ${names.map((name, index) => `${sf(name)}: url(${urls[index]});`).join(" ")} }`
    document.head.append(sheet)
  })
  const pages = ovvi.pages.route(async (page) => {
    const { root, source } = parse(page.arg)
    for (const id of HOME) page.ovvi.controls.set(id, { hidden: source !== undefined })
    for (const id of DIFF) page.ovvi.controls.set(id, { hidden: source === undefined })
    if (source === undefined) await Home.make(page, root)
    else await (await import("./diff")).make(page, root, source)
  })
  await Promise.all([pages, symbols])
}
