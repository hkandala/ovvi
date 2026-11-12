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
  file: ["tree", "jump", "spacer", "wrap", "open-with"],
  preview: ["tree", "jump", "spacer", "open-with"],
  markdown: ["tree", "jump", "spacer", "mode", "lock", "open-with"],
}
const ALL = manifest.header.map((control) => control.id)

const load = (kind: Exclude<Kind, "files">): Promise<{ show(place: Place): Promise<Reveal> }> =>
  kind === "file" ? import("./file")
    : kind === "markdown" ? import("./markdown")
    : import("./preview")

export default async function main(ovvi: Ovvi) {
  const side = sidebar(ovvi)
  ovvi.on("control", ({ id, value }) => {
    const file = ovvi.card.arg, html = htmlPage(ovvi, file)
    if (id === "tree") side.toggle(value === true)
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
    if (place === "files") {
      // The page stays empty: the card's tree shows over it, with this page's row 2.
      scoped.on("place", ({ at }) => void side.page(scoped, arg, at))
      scoped.on("control", (event) => side.emit("control", event))
      scoped.on("find", () => side.emit("find"))
      return side.page(scoped, arg, page.at)
    }
    // Each page keeps its own row 2: a page shown again, or a setting, follows the card's sidebar.
    const sync = () => scoped.controls.set("tree", { value: side.open })
    const shows = () => (sync(), side.file(arg))
    shows()
    scoped.on("place", shows)
    scoped.on("settings", sync)
    const read = place === "file" || place === "markdown" ? ovvi.files.read(arg) : undefined
    read?.catch(() => undefined)
    const [code, crumbs] = await Promise.all([load(place), trail(scoped, arg)])
    // Each folder in the path closes the file: the card shows the tree, with the file selected.
    scoped.controls.set("jump", { value: crumbs, symbol: "", links: crumbs.length - 1 })
    scoped.on("control", ({ id, part }) => {
      if (id !== "jump" || part === undefined) return
      const folder = `${arg.split("/").slice(0, part + 1 - crumbs.length).join("/")}/`
      ovvi.card.go(side.rootFor(folder), { at: arg })
    })
    const reveal = await code.show(Object.assign(page, { read, trail: crumbs }))
    if (reveal) scoped.on("place", ({ at }) => at && reveal(at))
  })
}
