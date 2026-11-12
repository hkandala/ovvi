import type { Off, Ovvi } from "@ovvi/plugin-api"
import { choose, own, type Place, type Reveal } from "./place"

/** The tree beside a file: one for the card, over every file's page, so it keeps its open folders and its scroll while
 *  the card shows one file after another. It draws as the tree's page does (files.ts), but in its own root: a folder
 *  opened in it, or `..`, roots it there, and leaves the card where it is. */
export function sidebar(ovvi: Ovvi) {
  const aside = document.body.appendChild(document.createElement("aside"))
  aside.id = "side"
  const grip = Object.assign(document.createElement("div"), { className: "grip" })
  aside.append(grip)
  const width = (px: number) => document.body.style.setProperty("--side-width", `${px}px`)
  width(own(ovvi).sideWidth ?? 220)
  grip.onpointerdown = (event) => {
    grip.setPointerCapture(event.pointerId)
    grip.onpointermove = (move) => width(Math.round(Math.min(Math.max(move.clientX, 140), innerWidth * 0.6)))
    grip.onpointerup = () => {
      grip.onpointermove = grip.onpointerup = null
      choose(ovvi, { sideWidth: parseInt(document.body.style.getPropertyValue("--side-width")) })
    }
  }

  const chosen = () => own(ovvi).side ?? ovvi.settings.get<string>("file-tree") === "tree"
  /** The root the card's tree last showed: the sidebar starts there. */
  let wanted = "", file = "", drawn = "", reveal: Reveal, drop: Off | undefined
  ovvi.on("settings", (changed) => "file-tree" in changed && show())

  function draw(root: string) {
    drop?.()
    drawn = root
    reveal = undefined
    const offs: Off[] = [], held = (off: Off) => (offs.push(off), off)
    let dropped = false
    drop = () => {
      dropped = true
      for (const off of offs.splice(0)) off()
      element.remove()
    }
    const element = aside.insertBefore(document.createElement("div"), grip)
    element.dataset.place = "files"
    // The header and ⌘F are the file's.
    const scoped: Ovvi = Object.create(ovvi, {
      on: { value: (event: string, fn: never) => (["control", "find"].includes(event) ? () => {} : held(ovvi.on(event as "settings", fn))) },
      controls: { value: { get: () => undefined, set: () => {} } },
      files: { value: Object.create(ovvi.files, { watch: { value: (path: string, fn: () => void) => held(ovvi.files.watch(path, fn)) } }) },
      card: { value: Object.create(ovvi.card, { go: { value: (arg: string) => draw(arg) } }) },
      open: {
        value: (arg: string, options?: Parameters<Ovvi["open"]>[1]) =>
          options?.how === "card" && arg.endsWith("/") ? Promise.resolve(draw(arg)) : ovvi.open(arg, options),
      },
    })
    const place: Place = {
      arg: root, at: file, element, ovvi: scoped, trail: [], shown: false, keep: held, redraw: () => {},
      get dropped() {
        return dropped
      },
    }
    void import("./files").then(({ show }) => show(place)).then((found) => {
      if (!dropped) reveal = found
    }, console.error)
  }

  function show() {
    const on = chosen()
    document.body.toggleAttribute("data-side", on)
    if (!on || !file) return
    if (!drawn || (wanted && wanted !== drawn)) draw(wanted || file.slice(0, file.lastIndexOf("/") + 1))
    else reveal?.(file)
    wanted = ""
  }

  return {
    get open() {
      return chosen()
    },
    /** The card shows this file. */
    file(path: string) {
      file = path
      show()
    },
    /** The card's tree shows this root. */
    root(folder: string) {
      wanted = folder
    },
    toggle(on: boolean) {
      choose(ovvi, { side: on })
      show()
    },
    /** Where a closed file leaves the card: the tree beside it, else the file's folder. */
    rootFor(path: string) {
      const root = wanted || drawn
      return root && path.startsWith(root) ? root : path.slice(0, path.lastIndexOf("/") + 1)
    },
  }
}
