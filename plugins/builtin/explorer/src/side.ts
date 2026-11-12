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
  let px = own(ovvi).sideWidth ?? 220
  const width = () => document.body.style.setProperty("--side-width", `${px}px`)
  width()
  grip.onpointerdown = (event) => {
    grip.setPointerCapture(event.pointerId)
    grip.onpointermove = (move) => {
      px = Math.round(Math.min(Math.max(move.clientX, 140), innerWidth * 0.6))
      width()
    }
    grip.onpointerup = () => {
      grip.onpointermove = grip.onpointerup = null
      choose(ovvi, { sideWidth: px })
    }
  }

  const chosen = () => own(ovvi).side ?? ovvi.settings.get<string>("file-tree") === "tree"
  /** The root the card's tree last showed: the sidebar starts there. */
  let wanted = "", file = "", drawn = "", dots: boolean | undefined, reveal: Reveal, drop: Off | undefined
  ovvi.on("settings", (changed) => "file-tree" in changed && show())

  function draw(root: string) {
    drop?.()
    drawn = root
    dots = own(ovvi).hiddenFiles
    reveal = undefined
    const offs: Off[] = []
    let dropped = false
    const held = (off: Off) => (dropped ? off() : offs.push(off), off)
    drop = () => {
      dropped = true
      for (const off of offs.splice(0)) off()
      element.remove()
    }
    const element = aside.insertBefore(document.createElement("div"), grip)
    element.dataset.place = "files"
    // The header and ⌘F are the file's. ponytail: its own watch of the root and the hidden status bar's git reads, beside
    // a kept tree page of the same root; share the runtime's watch if remote cards get slow.
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
      if (dropped) return
      reveal = found
      if (file !== place.at) found?.(file)
    }, console.error)
  }

  function show() {
    const on = chosen()
    document.body.toggleAttribute("data-side", on)
    if (!on) return give()
    if (!file) return
    if (!drawn || (wanted && wanted !== drawn) || own(ovvi).hiddenFiles !== dots) {
      draw(wanted || drawn || file.slice(0, file.lastIndexOf("/") + 1))
    } else {
      reveal?.(file)
    }
    wanted = ""
  }

  /** A hidden tree gives the keys to the page, as the runtime's `present` does. */
  function give() {
    let at = document.activeElement
    if (!at || !aside.contains(at)) return
    while (at.shadowRoot?.activeElement) at = at.shadowRoot.activeElement
    if (at instanceof HTMLElement) at.blur()
    dispatchEvent(new Event("focus"))
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
