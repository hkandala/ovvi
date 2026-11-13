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
  const aside = document.body.appendChild(document.createElement("div"))
  aside.id = "side"
  const grip = Object.assign(document.createElement("div"), { className: "grip" })
  aside.append(grip)
  aside.addEventListener("transitionend", (event) =>
    event.target === aside && event.propertyName === "translate" && document.body.removeAttribute("data-slide"))
  let px = own(ovvi).sideWidth ?? 280
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
  // From the start: only a change of it beside a file slides.
  document.body.toggleAttribute("data-side", chosen())
  /** As files.css lays it out: the card shows the tree's page. */
  const paged = () => Boolean(document.body.querySelector(':scope > .ovvi-page[data-place="files"]:not([inert])'))
  const folder = (path: string) => path.slice(0, path.lastIndexOf("/") + 1)
  /** The last shown last. */
  let trees: Tree[] = [], current: Tree | undefined, file = "", next = ""
  ovvi.on("settings", (changed) => "file-tree" in changed && show())

  function draw(root: string, at?: string): Tree {
    const offs: Off[] = []
    let dropped = false
    const held = (off: Off) => (dropped ? off() : offs.push(off), off)
    const element = aside.insertBefore(document.createElement("div"), grip)
    element.dataset.place = "files"
    element.inert = true
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
          go: {
            value: (arg: string, options?: { at?: string }) =>
              void (paged() ? ovvi.card.go(arg, options) : rooted(arg, file || undefined)),
          },
        }),
      },
      open: {
        value: (arg: string, options?: Parameters<Ovvi["open"]>[1]) =>
          options?.how === "card" && arg.endsWith("/") && !paged() ? rooted(arg, file || undefined) : ovvi.open(arg, options),
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

  /** The tree of this root shows, with `at` selected, once it has its rows: until then the card shows what it showed.
   *  It shows only if no other root was asked for meanwhile, and `still` holds. */
  async function rooted(root: string, at?: string, still = () => true) {
    next = root
    const found = trees.find((each) => each.root === root)
    const tree = found ?? draw(root, at)
    if (found && at) void tree.reveal.then((reveal) => reveal?.(at))
    else if (!found) trees.push(tree)
    await tree.reveal
    if (next !== root || !still() || !trees.includes(tree)) return
    trees = [...trees.filter((each) => each !== tree), tree]
    for (const old of trees.splice(0, Math.max(0, trees.length - 5))) old.drop()
    current = tree
    for (const each of trees) each.element.inert = each !== tree
    for (const fn of tree.due) fn()
    tree.due.clear()
  }

  /** Beside a file, a change slides the tree; the slide's end clears `data-slide`. */
  function side(on: boolean) {
    if (file && on !== document.body.hasAttribute("data-side")) document.body.toggleAttribute("data-slide", true)
    document.body.toggleAttribute("data-side", on)
  }

  function show(keys?: () => boolean) {
    const on = chosen()
    if (!file || !on) side(on)
    if (!file) return
    if (!on) return give()
    // A tree not drawn yet slides in once it has its rows, not empty.
    void (current ? Promise.resolve() : rooted(folder(file), file)).then(() => {
      if (file) side(chosen())
      return current?.reveal.then((reveal) => reveal?.(file, keys))
    })
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
      const shown = rooted(root, at, () => ovvi.card.arg === root)
      const tree = trees.find((each) => each.root === root)
      if (tree) tree.header = header
      for (const [id, change] of tree?.values ?? []) header.controls.set(id, change)
      await shown
    },
    /** Row 2 of the tree's page, and its ⌘F. */
    emit(event: "control" | "find", data?: unknown) {
      for (const fn of current?.handlers[event] ?? []) fn(data as never)
    },
    toggle(on: boolean) {
      choose(ovvi, { side: on })
      show()
    },
    /** Switch Between Tree and File (⇧⌘E): from the file to its row in the tree, shown if hidden, and back. */
    keys() {
      if (aside.contains(document.activeElement)) return give()
      // Only if the keyboard stayed: a slow remote listing must not take it from what the user went on to.
      const before = document.activeElement
      choose(ovvi, { side: true })
      show(() => document.activeElement === before)
    },
    /** Where a file closed from its path's folder leaves the card: the tree beside it, kept, when it holds the
     *  folder, else that folder's tree. */
    rootFor(path: string) {
      const root = current?.root
      return root && path.startsWith(root) ? root : path
    },
  }
}
