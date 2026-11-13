import { FileTree, type FileTreeBatchOperation, type FileTreeDirectoryHandle, type FileTreeRenameEvent,
  type GitStatus } from "@pierre/trees"
import type { Change, OvviError } from "@ovvi/plugin-api"
import { footer } from "./footer"
import { stack } from "./stack"
import { choose, how, menu, name, open, own, type Place, type Reveal, sf, symbols } from "./place"

const STATUS: Record<string, GitStatus> = {
  M: "modified", T: "modified", C: "modified", A: "added", D: "deleted", R: "renamed", U: "untracked",
}
const parent = (path: string) => path.slice(0, path.lastIndexOf("/", path.length - 2) + 1)
/** ponytail: a name at the root that starts with a character that sorts ahead of `.` (`-`, `(`, `#`) sorts above
 *  `..`; a comparator of our own if that matters. */
const UP = "../"

const sprite = `<svg data-icon-sprite aria-hidden="true" width="0" height="0">
  <symbol id="ovvi-chevron" viewBox="0 0 16 16"><path d="M4.5 6.25 8 9.75l3.5-3.5" fill="none" stroke="currentColor"
    stroke-width="1.5" stroke-linecap="round" stroke-linejoin="round"/></symbol>
</svg>`

// The filter's matches are a second tree: Pierre's own search matches the whole path.
const look = {
  flattenEmptyDirectories: false,
  stickyFolders: true,
  icons: {
    set: "complete" as const,
    spriteSheet: sprite,
    remap: { "file-tree-icon-chevron": "ovvi-chevron" },
  },
  unsafeCSS: `:host {
    --trees-bg-override: transparent; --trees-fg-override: var(--text); --trees-fg-muted-override: var(--dim);
    --trees-accent-override: var(--accent); --trees-font-size-override: var(--font-size);
    --trees-padding-inline-override: 6px; --trees-border-color-override: var(--divider);
    --trees-item-height: 24px; --trees-border-radius-override: 6px; --trees-level-gap-override: 12px;
    --trees-item-row-gap-override: 5px; --trees-item-padding-x-override: 6px;
    --trees-bg-muted-override: color-mix(in srgb, var(--text) 6%, transparent);
    --trees-selected-bg-override: color-mix(in srgb, var(--accent) 24%, transparent);
    --trees-selected-fg-override: var(--text); --trees-focus-ring-width-override: 1.5px;
    --trees-focus-ring-color-override: var(--accent); --trees-focus-ring-offset-override: -1.5px;
    --trees-selected-focused-border-color-override: var(--accent);
    --trees-indent-guide-bg-override: var(--divider);
    --trees-git-modified-color-override: var(--needs-you); --trees-git-deleted-color-override: var(--error);
    --trees-git-added-color-override: var(--finished); --trees-git-untracked-color-override: var(--finished);
    --trees-git-renamed-color-override: var(--finished);
  }
  /* As the Finder's list: the selection in gray while the tree does not have the keyboard. */
  :host(:not(:focus-within)) { --trees-selected-bg-override: color-mix(in srgb, var(--text) 12%, transparent); }
  [data-item-contains-git-change="true"] > [data-item-section="git"] { opacity: 1; }
  [data-type="item"] > [data-item-section="icon"] { width: 34px; justify-content: flex-end; color: var(--dim); }
  [data-item-type="folder"] > [data-item-section="icon"] { justify-content: space-between; }
  [data-item-type="folder"] > [data-item-section="icon"]::after { content: ""; flex: none; width: 16px; height: 16px;
    background: var(--folder-blue); -webkit-mask: var(--folder) center / 16px no-repeat; }
  [data-item-path="${UP}"] > [data-item-section="icon"] > svg { visibility: hidden; }
  [data-item-selected="true"] > [data-item-section="icon"] { color: var(--dim); }
  /* A long name on one line, cut at its end, as VS Code's explorer: Pierre cuts it in the middle, under a marker that
     needs an opaque row to hide the letters below it. Pierre's own markup (1.0.0-beta.6): check it on an update. */
  [data-item-section="content"] { white-space: nowrap; }
  [data-item-section="content"] :is([data-truncate-group-container], [data-truncate-segment-priority],
    [data-truncate-container], [data-truncate-grid], [data-truncate-grid] > div) { display: contents; }
  [data-item-section="content"] [data-truncate-content="visible"] { display: inline; direction: ltr; }
  [data-item-section="content"] :is([data-truncate-content="overflow"], [data-truncate-marker-cell],
    [data-truncate-fill]) { display: none !important; }
  /* The sticky folders on the card, with no band (stack.ts): the view masked under them, their copy over it. */
  :host { position: relative; }
  :host([data-stack]) [data-file-tree-virtualized-scroll] {
    -webkit-mask: linear-gradient(transparent var(--stack), #000 var(--stack)); }
  [data-stack-copy] { position: absolute; z-index: 5; }
  [data-stack-copy] [data-hover]:not([data-item-selected="true"]) { background-color: var(--trees-bg-muted); }
  /* Inside its box: the row's name clips what goes past it. */
  [data-item-rename-input] { border-radius: 4px; background: var(--card); outline: 1.5px solid var(--accent);
    outline-offset: -1.5px; }
  :host(:not([data-keys])) [data-type="item"]::before { outline: none !important; }`,
}
const dotted = (path: string) => /(^|\/)\.[^/]/.test(path)

export async function show(place: Place): Promise<Reveal> {
  const { ovvi, element: root, keep } = place
  const base = place.arg.replace(/\/$/, "")
  const top = base || "/"
  const folder = (path: string) => tree.getItem(path) as FileTreeDirectoryHandle | null
  const above = top === "/" ? "" : top.slice(0, top.lastIndexOf("/")) || "/"
  ovvi.controls.set("root", { value: top })
  const move = async (path?: string) => {
    const root = path ?? (await ovvi.pick.folder(top))
    if (!root) return
    if (!(await ovvi.files.info(root).then((info) => info.folder, () => false))) {
      return ovvi.controls.set("root", { refused: true })
    }
    ovvi.card.go(root === "/" ? "/" : `${root}/`)
  }
  let dotfiles = own(ovvi).hiddenFiles ?? ovvi.settings.get<boolean>("hidden-files")
  let dim = ovvi.settings.get<boolean>("ignored")
  /** The eye in row 2 and View ▸ Show Hidden Files (⇧⌘., as Finder's). */
  const eye = (yes: boolean) => {
    ovvi.controls.set("hidden-files", { value: yes })
    ovvi.controls.set("show-hidden", { checked: yes })
  }
  eye(dotfiles)

  /** `""` is the root; a folder's path ends in `/`, as the tree's. */
  const children = new Map<string, Set<string>>()
  const unlisted = new Set<string>()
  const ignored = new Set<string>()
  let changes: Change[] = []
  let filter = ""
  let paths: Promise<void> | undefined
  let matched = 0
  let failed = false

  let repo: string | null = null
  let repository = false
  // A failed call keeps what the tree knew, as a failed listing keeps its rows.
  const rooted = () => ovvi.git.root(top).catch(() => repo)

  root.innerHTML = `<div id="find" class="find" hidden><div class="find-row"><input class="find-field" placeholder="Filter"
    aria-label="Filter" spellcheck="false"><span class="find-count"></span><button class="find-icon" aria-label="Close Filter"
    title="Close"></button></div></div><div id="message" hidden><span
    class="symbol"></span><p></p></div><div id="tree"></div><div id="matches" hidden></div><footer hidden></footer>`
  const renaming = (own: () => FileTree) => ({
    canRename: (item: { path: string }) => item.path !== UP.slice(0, -1),
    onRename: (event: FileTreeRenameEvent) => void renamed(event, own()),
    // A name in use in the tree, empty, or with a `/`: the row keeps its name.
    onError: (error: string) => void ovvi.toast(error),
  })
  const tree = new FileTree({ paths: above ? [UP] : [], ...look, renaming: renaming(() => tree) })
  const results = new FileTree({ paths: [], ...look, renaming: renaming(() => results) })
  const host = root.querySelector<HTMLElement>("#tree")!
  const message = root.querySelector<HTMLElement>("#message")!
  const matches = root.querySelector<HTMLElement>("#matches")!
  const find = root.querySelector<HTMLElement>("#find")!
  const field = find.querySelector("input")!
  const count = find.querySelector<HTMLElement>(".find-count")!
  const bar = root.querySelector("footer")!, status = footer(ovvi, bar, () => void run(git))
  tree.render({ containerWrapper: host })
  results.render({ containerWrapper: matches })
  for (const each of [tree, results]) stack(each.getFileTreeContainer()!)
  // pierre counts an ignored path as a change of the folders above it: their dot shows only for git's changes.
  // ponytail: a style per tree in its shadow root; drop it when pierre leaves ignored paths out of its counts.
  const dots = [tree, results].map((each) => each.getFileTreeContainer()!.shadowRoot!.appendChild(document.createElement("style")))
  keep(() => {
    tree.cleanUp()
    results.cleanUp()
  })
  const ring = (on: boolean) => {
    root.toggleAttribute("data-keys", on)
    for (const each of [tree, results]) each.getFileTreeContainer()?.toggleAttribute("data-keys", on)
  }
  root.addEventListener("pointerdown", () => ring(false), true)

  /** One at a time: two listings of a folder at once would add its entries twice. */
  let queue = Promise.resolve()
  const run = (work: () => Promise<void>) => {
    const live = async () => (place.dropped ? undefined : work())
    return (queue = queue.then(live, live))
  }
  /** A change while a refresh waits joins it: a build writes many times a second. */
  let due = false

  function put(path: string, operations: FileTreeBatchOperation[]) {
    let added = false
    for (let at = path; at; at = parent(at)) {
      const set = children.get(parent(at)) ?? children.set(parent(at), new Set()).get(parent(at))!
      // A link to a folder or a submodule is a folder in a listing and a file in git's paths.
      if (set.has(at) || set.has(at.endsWith("/") ? at.slice(0, -1) : at + "/")) break
      set.add(at)
      if (at.endsWith("/")) unlisted.add(at)
      added = true
    }
    // The tree makes the folders above a path itself.
    if (added) operations.push({ type: "add", path })
  }

  function forget(path: string) {
    for (const child of children.get(path) ?? []) forget(child)
    children.delete(path)
    unlisted.delete(path)
    ignored.delete(path)
  }

  async function list(at: string, rooted?: Promise<string | null>) {
    unlisted.delete(at)
    let entries: { name: string; folder: boolean; ignored: boolean }[]
    try {
      entries = await ovvi.files.list(at ? `${base}/${at.slice(0, -1)}` : top)
    } catch (error) {
      // Only a missing folder empties the tree. Any other failure (a remote machine's dropped link, its 10 s bound)
      // keeps the rows: the watch calls again once the machine answers.
      if (at || (children.has("") && (error as OvviError).code !== "notFound")) return
      children.clear()
      unlisted.clear()
      ignored.clear()
      tree.resetPaths(above ? [UP] : [])
      failed = true
      show()
      return
    } finally {
      if (rooted) {
        repo = await rooted
        repository = repo === top
      }
    }
    if (!at) failed = false
    // An empty folder too: a refresh lists it again.
    if (!children.has(at)) children.set(at, new Set())
    const hidden = dotfiles ? 0 : entries.filter((entry) => entry.name.startsWith(".")).length
    if (!dotfiles) entries = entries.filter((entry) => !entry.name.startsWith("."))
    if (!at) status.folder(entries.filter((entry) => entry.folder).length, entries.filter((entry) => !entry.folder).length, hidden)
    const now = entries.map((entry) => at + entry.name + (entry.folder ? "/" : ""))
    const kept = new Set(now)
    const operations: FileTreeBatchOperation[] = []
    for (const path of children.get(at) ?? []) {
      if (kept.has(path)) continue
      children.get(at)?.delete(path)
      forget(path)
      operations.push({ type: "remove", path, recursive: true })
    }
    entries.forEach((entry, index) => {
      put(now[index], operations)
      if (entry.ignored && repository) ignored.add(now[index])
      else ignored.delete(now[index])
    })
    tree.batch(operations)
    showStatus()
    if (!at) show()
  }

  function show() {
    const none = Boolean(filter) && !matched, empty = !filter && !failed && children.get("")?.size === 0
    message.hidden = !failed && !none && !empty
    bar.hidden = failed
    message.querySelector("p")!.textContent = failed ? `Can't list ${top}`
      : none ? "No matching files" : empty ? "This folder is empty" : ""
    const icon = failed ? "folder.badge.questionmark" : empty ? "folder" : "magnifyingglass"
    if (!message.hidden && message.dataset.icon !== icon) {
      message.dataset.icon = icon
      void ovvi.symbol(icon, 30).then((url) => message.style.setProperty("--symbol", `url(${url})`), () => {})
    }
  }

  /** ponytail: the first 5,000; a search on the machine when roots get bigger. */
  function match() {
    const text = filter.toLowerCase()
    const named = (path: string) => path.slice(path.lastIndexOf("/") + 1).toLowerCase().includes(text)
    const found = [...children.values()].flatMap((set) =>
      [...set].filter((path) => !path.endsWith("/") && (dotfiles || !dotted(path)) && named(path)),
    ).slice(0, 5000)
    matched = found.length
    count.textContent = filter ? String(matched) : ""
    host.hidden = Boolean(filter)
    matches.hidden = !filter
    results.resetPaths(filter ? found : [], { initialExpandedPaths: [...new Set(found.flatMap(folders))] })
    show()
  }

  function folders(path: string): string[] {
    const above = parent(path)
    return above ? [above, ...folders(above)] : []
  }

  function showStatus() {
    const letters = repository ? changes : []
    const status = [
      ...letters.flatMap(({ letter, path }) => (STATUS[letter] ? [{ path, status: STATUS[letter] }] : [])),
      ...(dim ? [...ignored] : []).map((path) => ({ path, status: "ignored" as const })),
    ]
    tree.setGitStatus(status)
    results.setGitStatus(status)
    const changed = [...new Set(letters.flatMap((change) => folders(change.path)))]
    // As specific as the rule that hides them, and after it: it wins.
    const shown = changed.map((path) =>
      `[data-item-path="${CSS.escape(path)}"]:not([data-item-git-status]) > [data-item-section="git"]`)
    const css = `[data-item-contains-git-change]:not([data-item-git-status]) > [data-item-section="git"] {
      visibility: hidden; }
      ${shown.length ? `${shown.join(", ")} { visibility: visible; }` : ""}`
    // Only on a change: a new style restyles the whole tree, and an agent's edits refresh it often.
    for (const style of dots) if (style.textContent !== css) style.textContent = css
  }

  async function refresh() {
    await list("", rooted())
    await git()
    for (const at of [...children.keys()]) {
      if (!at || unlisted.has(at) || !children.has(at)) continue
      if (folder(at)?.isExpanded()) await list(at)
      else unlisted.add(at)
    }
  }

  /** The plumbing `diff-index` never writes the index, so it leaves no `index.lock` in an agent's way.
   *  ponytail: `--numstat` leaves untracked files out; count them too if the bar should match Git's diff. */
  async function git() {
    const at = repo
    // The letters and the head from one `git status`.
    const [now, numstat] = at ? await Promise.all([ovvi.git.changes(at).catch(() => undefined),
      ovvi.run(["git", "--no-optional-locks", "diff-index", "--numstat", "HEAD"], { cwd: at }).catch(() => null)])
      : [{ status: [], head: null }, null]
    // A failed read keeps the bar, as it keeps the letters.
    const head = now?.head
    changes = now?.status ?? changes
    showStatus()
    const lines = { added: 0, removed: 0 }
    // Binary files count `-`.
    for (const [plus, minus] of (numstat?.code === 0 ? numstat.stdout : "").split("\n").map((line) => line.split("\t"))) {
      lines.added += Number(plus) || 0
      lines.removed += Number(minus) || 0
    }
    if (head !== undefined) status.repo(at, head, lines)
  }

  /** The tree moved its row already. */
  async function renamed(event: FileTreeRenameEvent, own: FileTree) {
    const slash = event.isFolder ? "/" : "", from = event.sourcePath + slash, to = event.destinationPath + slash
    rekey(from, to)
    const other = own === tree ? results : tree
    if (other.getItem(from)) other.move(from, to)
    try {
      await ovvi.files.move(`${base}/${event.sourcePath}`, `${base}/${event.destinationPath}`)
    } catch (error) {
      rekey(to, from)
      for (const each of [tree, results]) if (each.getItem(to)) each.move(to, from)
      void ovvi.toast(String((error as Error).message ?? error))
    }
  }

  function rekey(from: string, to: string) {
    const swap = (path: string) =>
      path === from || (from.endsWith("/") && path.startsWith(from)) ? to + path.slice(from.length) : path
    for (const [at, set] of [...children]) {
      children.delete(at)
      children.set(swap(at), new Set([...set].map(swap)))
    }
    for (const set of [unlisted, ignored]) {
      for (const path of [...set]) set.delete(path) && set.add(swap(path))
    }
  }

  async function reveal(path: string, offset?: "nearest") {
    // The tree beside a file shows no row of a file outside its root.
    if (!path.startsWith(`${base}/`)) return clear()
    const relative = path.slice(base.length + 1)
    if (!dotfiles && dotted(relative)) {
      dotfiles = true
      choose(ovvi, { hiddenFiles: true })
      eye(true)
      await refresh()
    }
    for (const above of folders(relative).reverse()) {
      if (unlisted.has(above) || !children.has(above)) await list(above)
      folder(above)?.expand()
    }
    const item = tree.getItem(relative) ?? tree.getItem(`${relative}/`)
    if (!item) return
    only(tree, item.getPath())
    tree.focusPath(item.getPath())
    tree.scrollToPath(item.getPath(), offset && { offset })
  }

  // ponytail: walks every folder not listed at each change of the tree (after a filter, all of the repository's); walk
  // the visible rows if a big repository's arrow keys lag.
  keep(tree.subscribe(() => {
    for (const at of unlisted) {
      if (!folder(at)?.isExpanded()) continue
      unlisted.delete(at)
      run(() => list(at))
    }
  }))

  ovvi.on("control", ({ id, value }) => {
    clear()
    if (id === "filter") {
      if (value === true) openFind()
      else closeFind()
    } else if (id === "collapse") {
      for (const at of children.keys()) if (at) folder(at)?.collapse()
    } else if (id === "root") {
      void move(value === undefined ? undefined : String(value))
    } else if (id === "hidden-files" || id === "show-hidden") {
      const yes = id === "hidden-files" ? value === true : !dotfiles
      choose(ovvi, { hiddenFiles: yes })
      eye(yes)
      showDotfiles(yes)
    }
  })
  ovvi.on("settings", (changed) => {
    if ("ignored" in changed) {
      dim = changed.ignored === true
      showStatus()
    }
    if ("hidden-files" in changed && own(ovvi).hiddenFiles === undefined) {
      const yes = changed["hidden-files"] === true
      eye(yes)
      showDotfiles(yes)
    }
  })

  function showDotfiles(yes: boolean) {
    dotfiles = yes
    run(refresh).catch(console.error)
    paths = filter ? run(loadPaths).catch(() => {}) : undefined
    void (paths ?? queue).then(match).catch(console.error)
  }
  ovvi.on("find", () => openFind())

  function openFind(text?: string) {
    find.hidden = false
    ovvi.controls.set("filter", { value: true })
    if (text !== undefined) {
      field.value = text
      filtered()
    } else {
      field.select()
    }
    field.focus()
  }

  function closeFind() {
    find.hidden = true
    ovvi.controls.set("filter", { value: false })
    if (field.value) {
      field.value = ""
      filtered()
    }
    take()
  }

  function filtered() {
    filter = field.value
    paths ??= filter ? run(loadPaths).catch(() => {}) : undefined
    void (paths ?? queue).then(match).catch(console.error)
  }
  field.oninput = filtered
  field.onkeydown = (event) => {
    if (event.key === "Escape") closeFind()
    else if (event.key === "Enter" || event.key === "ArrowDown") take()
    else return
    event.preventDefault()
  }
  const close = find.querySelector("button")!
  close.onclick = closeFind
  symbols(ovvi, ["xmark"])
  close.style.setProperty("--symbol", `var(${sf("xmark")})`)

  ovvi.files.watch(top, () => {
    if (due) return
    due = true
    if (!filter) paths = undefined
    run(async () => {
      due = false
      await refresh()
      if (filter) match()
    }).catch(console.error)
  })

  async function loadPaths() {
    const operations: FileTreeBatchOperation[] = []
    for (const path of await ovvi.files.paths(top).catch(() => [])) {
      if (dotfiles || !dotted(path)) put(path, operations)
    }
    tree.batch(operations)
  }

  const row = (event: Event) => {
    const node = event.composedPath().find((n): n is HTMLElement => n instanceof HTMLElement && Boolean(n.dataset.itemPath))
    const id = node?.dataset.itemPath
    return id === undefined ? undefined : { id, arg: arg(id), folder: node!.dataset.itemType === "folder" }
  }
  const arg = (id: string) => id === UP ? (above === "/" ? "/" : `${above}/`) : `${base}/${id}`
  const chevron = (event: MouseEvent) => {
    const icon = event.composedPath().find((n): n is HTMLElement => n instanceof HTMLElement && n.dataset.itemSection === "icon")
    const right = icon?.querySelector("svg")?.getBoundingClientRect().right
    return right !== undefined && event.clientX <= right
  }

  for (const trees of [host, matches]) {
    // A cut name shows whole in a tooltip, as in the Finder. On each move: the list reuses its rows as it scrolls.
    trees.addEventListener("pointermove", (event) => {
      const node = event.composedPath().find((n): n is HTMLElement => n instanceof HTMLElement && Boolean(n.dataset.itemPath))
      const text = node?.querySelector<HTMLElement>('[data-item-section="content"]')
      const title = text && text.scrollWidth > text.clientWidth ? name(node!.dataset.itemPath!) : ""
      if (node && node.title !== title) node.title = title
    })
    // Captured ahead of the tree's own click: ⌘ adds to its selection, a click toggles a folder.
    trees.addEventListener(
      "click",
      (event) => {
        const at = row(event)
        if (!at) return clear()
        // A ⌘- or ⌥-double-click opens once.
        if (event.detail > 1 && (event.metaKey || event.altKey)) return event.stopPropagation()
        const toggle = at.folder && chevron(event)
        // VoiceOver's press on `..` (no clicks counted) goes up.
        if (event.metaKey || event.altKey || (event.detail >= 2 && !toggle) || (at.id === UP && !event.detail)) {
          event.stopPropagation()
          open(ovvi, at.arg, how(event))
        } else if (at.folder && !toggle && event.detail === 1 && !event.shiftKey && !event.ctrlKey) {
          event.stopPropagation()
          only(filter ? results : tree, at.id)
          take(at.id)
        }
      },
      true,
    )
    trees.addEventListener("keydown", keys, true)
    trees.addEventListener("contextmenu", (event) => {
      // The rename's field has its own.
      if (event.composedPath()[0] instanceof HTMLInputElement) return
      const at = row(event)
      if (!at) return event.preventDefault()
      const shown = filter ? results : tree
      void menu(ovvi, event, at.arg, { rename: at.id === UP ? undefined : () => shown.startRenaming(at.id) && stem(shown, at.id) })
    })
  }

  function keys(event: KeyboardEvent) {
    // The rename's field has its own.
    if (event.composedPath()[0] instanceof HTMLInputElement) return
    const shown = filter ? results : tree, key = event.key
    const plain = !event.shiftKey && !event.metaKey && !event.altKey && !event.ctrlKey
    const command = event.metaKey && !event.shiftKey && !event.altKey && !event.ctrlKey
    const moved = root.hasAttribute("data-keys"), selected = shown.getSelectedPaths().length > 0
    const at = moved || selected ? shown.getFocusedPath() : null
    if (key.startsWith("Arrow")) ring(true)
    if (plain && key === "Enter") {
      if (at && shown.startRenaming(at)) stem(shown, at)
    } else if (command && (key === "o" || key === "ArrowDown")) {
      if (at) open(ovvi, arg(at), "card")
    } else if (command && key === "ArrowUp") {
      if (above) ovvi.card.go(arg(UP))
    } else if (plain && key === "Escape" && !find.hidden) {
      closeFind()
    } else if (key.length === 1 && key !== " " && !event.metaKey && !event.ctrlKey && !event.altKey) {
      openFind(filter + key)
    } else if (plain && (key === "ArrowDown" || key === "ArrowUp") && !moved && !selected) {
      if (key === "ArrowUp") shown.focusLastItem()
      else shown.focusFirstItem()
    } else if (!(plain && key === " ")) {
      return
    }
    event.preventDefault()
    event.stopPropagation()
  }

  /** The tree selects the whole name a frame after the rename starts. */
  function stem(shown: FileTree, at: string) {
    requestAnimationFrame(() => {
      const field = shown.getFileTreeContainer()?.shadowRoot?.querySelector<HTMLInputElement>("[data-item-rename-input]")
      const dot = field?.value.lastIndexOf(".") ?? 0
      if (field && dot > 0 && !at.endsWith("/")) field.setSelectionRange(0, dot)
    })
  }

  function clear() {
    for (const each of [tree, results]) for (const at of each.getSelectedPaths()) each.getItem(at)?.deselect()
  }

  /** A kept tree still has the row it opened selected. */
  function only(shown: FileTree, path: string) {
    clear()
    shown.getItem(path)?.select()
  }

  function take(path?: string) {
    const shown = filter ? results : tree
    path ??= shown.getFocusedPath() ?? shown.getVisibleRows(0, 0)[0]?.path
    if (!path) return
    // Any row first: the tree moves the keyboard to its focused row only while it holds it.
    const any = shown.getFileTreeContainer()?.shadowRoot?.querySelector<HTMLElement>("button[data-item-path]")
    any?.focus({ preventScroll: true })
    shown.focusPath(path)
  }
  // A frame later, so a click that gave a row the keyboard keeps it: else the tree scrolls to its prior row between
  // the press and the release.
  const given = () => requestAnimationFrame(() => {
    if (place.shown && document.activeElement !== field
      && !(filter ? results : tree).getFileTreeContainer()?.shadowRoot?.activeElement) {
      take()
    }
  })
  addEventListener("focus", given)
  keep(() => removeEventListener("focus", given))

  // One wait for the first listing and the repository: each starts a process.
  await run(() => list("", rooted()))
  if (place.at) await run(() => reveal(place.at!))
  run(git)
  return (at, keys) => void run(async () => {
    await reveal(at, "nearest")
    if (!keys?.()) return
    ring(true)
    take()
  })
}
