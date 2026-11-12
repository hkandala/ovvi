import type { Off, Ovvi } from "@ovvi/plugin-api"
import { choose, own, type Place, type Reveal } from "./place"

type Handler = (data: never) => void
type Tree = {
  root: string
  element: HTMLElement
  reveal: Promise<Reveal>
  drop: () => void
  /** Its watches' calls while another tree shows. */
  due: Set<() => void>
  /** Its row 2, for the tree's page of its root. */
  values: Map<string, Record<string, unknown>>
  header?: Ovvi
  handlers: Record<"control" | "find", Set<Handler>>
}

/** The card's tree, outside the routed pages: the tree's page and the tree beside a file are one tree, so its open
 *  folders, selection and scroll stay as the card goes from the tree to a file and back, and from file to file. It
 *  draws as files.ts does, one per root, the last five, as the runtime keeps pages. On the tree's page the row 2 is
 *  the tree's; beside a file the row 2 is the file's, and a folder opened in the tree, or `..`, roots it there and
 *  leaves the card where it is. */
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
  /** As files.css lays it out: the card shows the tree's page. */
  const paged = () => Boolean(document.body.querySelector(':scope > .ovvi-page[data-place="files"]:not([inert])'))
  const folder = (path: string) => path.slice(0, path.lastIndexOf("/") + 1)
  /** The last shown last. */
  let trees: Tree[] = [], current: Tree | undefined, file = ""
  ovvi.on("settings", (changed) => "file-tree" in changed && show())

  function draw(root: string, at?: string): Tree {
    const offs: Off[] = []
    let dropped = false
    const held = (off: Off) => (dropped ? off() : offs.push(off), off)
    const element = aside.insertBefore(document.createElement("div"), grip)
    element.dataset.place = "files"
    const tree: Tree = {
      root, element, reveal: Promise.resolve(undefined), due: new Set(), values: new Map(),
      handlers: { control: new Set(), find: new Set() },
      drop: () => {
        dropped = true
        for (const off of offs.splice(0)) off()
        element.remove()
      },
    }
    const scoped: Ovvi = Object.create(ovvi, {
      on: {
        value: (event: string, fn: never) => {
          if (event !== "control" && event !== "find") return held(ovvi.on(event as "settings", fn))
          tree.handlers[event].add(fn)
          return () => void tree.handlers[event].delete(fn)
        },
      },
      controls: {
        value: {
          get: (id: string) => tree.values.get(id)?.value,
          set: (id: string, change: Record<string, unknown>) => {
            const kept = { ...tree.values.get(id), ...change }
            delete kept.focus
            delete kept.refused
            tree.values.set(id, kept)
            tree.header?.controls.set(id, change)
          },
        },
      },
      files: {
        value: Object.create(ovvi.files, {
          watch: {
            value: (path: string, fn: () => void) =>
              held(ovvi.files.watch(path, () => (current === tree ? fn() : tree.due.add(fn)))),
          },
        }),
      },
      card: {
        value: Object.create(ovvi.card, {
          go: { value: (arg: string, options?: { at?: string }) => void (paged() ? ovvi.card.go(arg, options) : rooted(arg)) },
        }),
      },
      open: {
        value: (arg: string, options?: Parameters<Ovvi["open"]>[1]) =>
          options?.how === "card" && arg.endsWith("/") && !paged() ? Promise.resolve(void rooted(arg)) : ovvi.open(arg, options),
      },
    })
    const place: Place = {
      arg: root, at, element, ovvi: scoped, trail: [], keep: held, redraw: () => {},
      get shown() {
        return current === tree && paged()
      },
      get dropped() {
        return dropped
      },
    }
    tree.reveal = import("./files").then(({ show }) => show(place)).catch((error: unknown) => (console.error(error), undefined))
    return tree
  }

  /** The tree of this root shows, drawn the first time, with `at` selected. */
  function rooted(root: string, at?: string) {
    let tree = trees.find((each) => each.root === root)
    if (!tree) tree = draw(root, at)
    else if (at) void tree.reveal.then((reveal) => reveal?.(at))
    trees = [...trees.filter((each) => each !== tree), tree]
    for (const old of trees.splice(0, Math.max(0, trees.length - 5))) old.drop()
    current = tree
    for (const each of trees) {
      each.element.toggleAttribute("data-shown", each === tree)
      each.element.inert = each !== tree
    }
    for (const fn of tree.due) fn()
    tree.due.clear()
    return tree
  }

  function show() {
    const on = chosen()
    document.body.toggleAttribute("data-side", on)
    if (!file) return
    if (!on) return give()
    if (!current) rooted(folder(file), file)
    else void current.reveal.then((reveal) => reveal?.(file))
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
    /** The card shows the tree's page of this root, with that page's row 2: resolves once the tree has its rows. */
    async page(header: Ovvi, root: string, at?: string) {
      file = ""
      const tree = rooted(root, at)
      tree.header = header
      for (const [id, change] of tree.values) header.controls.set(id, change)
      await tree.reveal
    },
    /** Row 2 of the tree's page, and its ⌘F. */
    emit(event: "control" | "find", data?: unknown) {
      for (const fn of current?.handlers[event] ?? []) fn(data as never)
    },
    toggle(on: boolean) {
      choose(ovvi, { side: on })
      show()
    },
    /** Where a closed file leaves the card: the tree beside it, else the file's folder. */
    rootFor(path: string) {
      const root = current?.root
      return root && path.startsWith(root) ? root : folder(path)
    },
  }
}
