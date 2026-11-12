import type { Ovvi } from "@ovvi/plugin-api"
import "./explorer.css"
import "./files.css"
import "./find.css"
import "./markdown.css"
import "./preview.css"
import { ovvi as manifest } from "../package.json"
import { htmlPage, kind, open, type Place, type Reveal, trail } from "./place"
import { sidebar } from "./side"

type Kind = ReturnType<typeof kind>

const CONTROLS: Record<Kind, string[]> = {
  files: ["root", "filter", "collapse", "hidden-files"],
  file: ["tree", "jump", "spacer", "wrap", "open-with", "close-file"],
  preview: ["tree", "jump", "spacer", "open-with", "close-file"],
  markdown: ["tree", "jump", "spacer", "mode", "lock", "open-with", "close-file"],
}
const ALL = manifest.header.map((control) => control.id)

const load = (kind: Kind): Promise<{ show(place: Place): Promise<Reveal> }> =>
  kind === "files" ? import("./files")
    : kind === "file" ? import("./file")
    : kind === "markdown" ? import("./markdown")
    : import("./preview")

export default async function main(ovvi: Ovvi) {
  const side = sidebar(ovvi)
  ovvi.on("control", ({ id }) => {
    const file = ovvi.card.arg, html = htmlPage(ovvi, file)
    if (id === "close-file") ovvi.card.go(side.rootFor(file), { at: file })
    else if (id === "browser" && html) open(ovvi, html, "card", "browser")
  })
  await ovvi.pages.route(async (page) => {
    const { arg, element: root } = page, place = kind(arg), scoped = page.ovvi
    for (const id of ALL) {
      const hidden = !CONTROLS[place].includes(id)
      scoped.controls.set(id, id === "filter" ? { hidden, value: false } : { hidden })
    }
    scoped.controls.set("open-with", { value: place === "files" ? "" : arg })
    scoped.controls.set("browser", { hidden: place !== "file" || !htmlPage(scoped, arg) })
    if (place !== "markdown") scoped.controls.set("lock-editing", { enabled: false, checked: false })
    root.dataset.place = place
    // Each page keeps its own row 2: each follows the card's sidebar.
    const sync = () => place !== "files" && scoped.controls.set("tree", { value: side.open })
    const shows = () => (place === "files" ? side.root(arg) : (sync(), side.file(arg)))
    shows()
    scoped.on("place", shows)
    scoped.on("settings", sync)
    scoped.on("control", ({ id, value }) => {
      if (id !== "tree") return
      side.toggle(value === true)
      sync()
    })
    const read = place === "file" || place === "markdown" ? ovvi.files.read(arg) : undefined
    read?.catch(() => undefined)
    const [code, crumbs] = await Promise.all([load(place), place === "files" ? [] : trail(scoped, arg)])
    if (place !== "files") scoped.controls.set("jump", { value: crumbs, symbol: "" })
    const reveal = await code.show(Object.assign(page, { read, trail: crumbs }))
    if (reveal) scoped.on("place", ({ at }) => at && reveal(at))
  })
}
