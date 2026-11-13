import type { Page } from "@ovvi/plugin-api"
import {
  type FileDiffMetadata,
  type FileDiffOptions,
  parsePatchFiles,
  preloadHighlighter,
  VirtualizedFileDiff,
  Virtualizer,
} from "@pierre/diffs"
import {
  coalesce, element, failed as toast, fileIcon, home, type How, how, keep, kept, menu, nameAndFolder, open, ovvi, sf,
} from "./lib"

const MARGIN = 1500
const letters = { change: "M", "rename-pure": "R", "rename-changed": "R", new: "A", deleted: "D" }
/** pierre lays out on the next frame. */
const afterLayout = (fn: () => void) => requestAnimationFrame(() => requestAnimationFrame(fn))

type Box = { diff: FileDiffMetadata; node: HTMLElement; row: HTMLElement; lines: HTMLElement; folded: boolean
  near?: boolean; view?: VirtualizedFileDiff<undefined> }

function ago(date: Date) {
  const seconds = (date.getTime() - Date.now()) / 1000
  const units: [Intl.RelativeTimeFormatUnit, number][] = [["year", 31536000], ["month", 2592000], ["week", 604800],
    ["day", 86400], ["hour", 3600], ["minute", 60]]
  const [unit, size] = units.find(([, size]) => Math.abs(seconds) >= size) ?? ["second", 1]
  return new Intl.RelativeTimeFormat(undefined, { numeric: "auto" }).format(Math.round(seconds / size), unit)
}

function sums(file: FileDiffMetadata) {
  let added = 0
  let removed = 0
  for (const hunk of file.hunks) {
    added += hunk.additionLines
    removed += hunk.deletionLines
  }
  return { added, removed }
}

function counts(file: FileDiffMetadata) {
  const { added, removed } = sums(file)
  return [
    element("span", "added", added ? `+${added}` : ""),
    element("span", "removed", removed ? `−${removed}` : ""),
  ]
}

function letter(file: FileDiffMetadata) {
  return element("span", `letter ${letters[file.type]}`, letters[file.type])
}

function blocks(file: FileDiffMetadata) {
  return file.hunks.flatMap((hunk) => {
    let line = hunk.additionStart
    let old = hunk.deletionStart
    return hunk.hunkContent.flatMap((content) => {
      if (content.type === "context") {
        line += content.lines
        old += content.lines
        return []
      }
      const place = content.additions
        ? { id: file.name, lineNumber: line, side: "additions" as const }
        : { id: file.name, lineNumber: old, side: "deletions" as const }
      line += content.additions
      old += content.deletions
      return [place]
    })
  })
}

function newLine(file: FileDiffMetadata, number: number) {
  for (const hunk of file.hunks) {
    let line = hunk.additionStart
    let old = hunk.deletionStart
    for (const content of hunk.hunkContent) {
      const context = content.type === "context"
      const span = context ? content.lines : content.deletions
      if (number >= old && number < old + span) return context ? line + number - old : line + content.additions
      line += context ? content.lines : content.additions
      old += span
    }
  }
}

function text(file: FileDiffMetadata) {
  return `${file.deletionLines.join("")}\0${file.additionLines.join("")}`
}

export async function make(place: Page, root: string, source: string) {
  const api = place.ovvi
  const page = element("div")
  page.id = "diff"
  const nav = element("nav", "list ovvi-sidebar")
  const main = element("main", "diff")
  const content = element("div", "content")
  const failure = element("p", "failure")
  const clean = element("div", "placeholder")
  clean.hidden = true
  clean.innerHTML = `<span class="symbol"></span><h2></h2>`
  const find = element("div", "find")
  find.hidden = true
  find.innerHTML = `<input class="find-field" placeholder="Filter" aria-label="Filter" spellcheck="false"><span
    class="find-count" role="status"></span><button class="find-icon" aria-label="Close Filter" title="Close"></button>`
  const field = find.querySelector("input")!, count = find.querySelector<HTMLElement>(".find-count")!
  const about = element("header", "about")
  content.append(about)
  main.append(content)
  page.append(nav, main, failure, clean, find)
  place.element.append(page)

  let patch: string | undefined
  let files: FileDiffMetadata[] = []
  let boxes = new Map<string, Box>()
  let changes: { id: string; lineNumber: number; side: "additions" | "deletions" }[] = []
  let change = -1
  let filter = ""
  const viewed = new Map<string, string>()
  const own = kept()
  let split = (own.layout ?? ovvi.settings.get("diff-layout")) === "split"
  let wrap = own.wrap ?? ovvi.settings.get<boolean>("wrap")
  let list = own.list ?? ovvi.settings.get<boolean>("file-list")
  nav.toggleAttribute("data-closed", !list)

  // A box keeps the whole file's height, so its header is sticky in CSS alone.
  const virtualizer = new Virtualizer()
  virtualizer.setup(main, content)
  // Each view costs about 1.5 ms (pierre puts its icons in each box): 1.5 s for 1,000 files at once.
  const owners = new WeakMap<Element, Box>()
  const nearby = new IntersectionObserver((entries) => steady(() => {
    for (const entry of entries) {
      const box = owners.get(entry.target)
      if (!entry.isIntersecting || !box || box.near) continue
      box.near = true
      show(box)
    }
  }), { root: main, rootMargin: `${MARGIN}px 0px` })
  place.keep(() => {
    nearby.disconnect()
    for (const box of boxes.values()) box.view?.cleanUp()
    virtualizer.cleanUp()
  })

  const options: FileDiffOptions<undefined, undefined> = {
    theme: { dark: "pierre-dark", light: "pierre-light" },
    themeType: ovvi.theme.dark ? "dark" : "light",
    diffStyle: split ? "split" : "unified",
    overflow: overflow(),
    lineDiffType: "word",
    // `N unmodified lines`, not expandable: that needs each file's whole text.
    hunkSeparators: "line-info-basic",
    disableFileHeader: true,
    unsafeCSS: `
      :host {
        --diffs-light-bg: transparent !important;
        --diffs-dark-bg: transparent !important;
        --diffs-addition-color-override: var(--finished);
        --diffs-deletion-color-override: var(--error);
        --diffs-modified-color-override: var(--working);
        --diffs-bg-separator-override: transparent;
      }
      [data-line-type=change-addition] {
        --diffs-computed-diff-line-bg: color-mix(in srgb, var(--finished) 10%, transparent) !important;
      }
      [data-line-type=change-deletion] {
        --diffs-computed-diff-line-bg: color-mix(in srgb, var(--error) 10%, transparent) !important;
      }
      [data-line-type=change-addition] [data-diff-span] {
        background-color: color-mix(in srgb, var(--finished) 28%, transparent) !important;
      }
      [data-line-type=change-deletion] [data-diff-span] {
        background-color: color-mix(in srgb, var(--error) 28%, transparent) !important;
      }
      [data-separator] { border-block: 0.5px solid var(--divider) }
      [data-separator-content] { background: none !important; color: var(--dim) }`,
  }

  function fileOptions(box: Box): FileDiffOptions<undefined, undefined> {
    return {
      ...options,
      onLineClick: ({ event, lineNumber, annotationSide }) => {
        if ((event.metaKey || event.altKey) && box.diff.type !== "deleted") {
          openFile(box.diff.name, annotationSide === "additions" ? lineNumber : newLine(box.diff, lineNumber), how(event))
        }
      },
    }
  }

  function fileRow(box: Box) {
    const diff = box.diff, row = element("div", "file"), disclosure = element("button", "disclosure", "›")
    disclosure.ariaLabel = "Show or hide the file"
    disclosure.onclick = () => collapse(diff.name, !box.folded)
    const [base, dir] = nameAndFolder(diff.name)
    const name = element("span", "name", base)
    const folder = element("span", "folder", diff.prevName && diff.prevName !== diff.name ? `from ${diff.prevName}` : dir)
    row.title = diff.name
    row.append(disclosure, fileIcon(diff.name), name, folder, ...counts(diff), letter(diff), actions(diff))
    return row
  }

  function actions(diff: FileDiffMetadata) {
    const box = element("span", "actions"), label = element("label", "mark")
    const check = element("input")
    check.type = "checkbox"
    check.ariaLabel = `Viewed ${diff.name}`
    check.checked = viewed.has(diff.name)
    check.onchange = () => {
      if (check.checked) viewed.set(diff.name, text(diff))
      else viewed.delete(diff.name)
      collapse(diff.name, check.checked)
      nav.querySelector(`[data-id="${CSS.escape(diff.name)}"]`)?.classList.toggle("viewed", check.checked)
    }
    label.append(check, "Viewed")
    box.append(label)
    if (diff.type !== "deleted") {
      const open = element("button", "open", "Open File")
      open.ariaLabel = `Open ${diff.name}`
      open.onclick = (event) => openFile(diff.name, undefined, how(event))
      open.oncontextmenu = (event) => void menu(event, `${root}/${diff.name}`, {})
      box.append(open)
    }
    return box
  }

  /** pierre's heights: 20 pt a row, 32 pt a hunk's gap, 8 pt above and below; the wrap is made up when it draws. */
  function show(box: Box) {
    const bare = box.folded || !box.diff.hunks.length
    box.node.classList.toggle("folded", bare)
    box.lines.hidden = bare
    box.row.querySelector(".disclosure")!.classList.toggle("shut", box.folded)
    if (bare || box.view) return
    if (!box.near) {
      box.lines.style.height = `${(split ? box.diff.splitLineCount : box.diff.unifiedLineCount) * 20 + box.diff.hunks.length * 32 + 16}px`
      return
    }
    box.lines.style.height = ""
    box.view = new VirtualizedFileDiff(fileOptions(box), virtualizer)
    box.view.render({ fileDiff: box.diff, fileContainer: box.lines })
  }

  /** A box above the first box in view that changes height moves it. pierre's own anchor comes a frame later;
   *  `overflow-anchor` is off, as it would move it twice. */
  function steady(work: () => void) {
    if (!main.scrollTop) return work()
    const view = main.getBoundingClientRect().top
    const anchor = [...boxes.values()].find((box) => box.node.getBoundingClientRect().bottom > view)
    const offset = anchor ? top(anchor.node) - main.scrollTop : 0
    work()
    if (anchor?.node.isConnected) main.scrollTop = anchor.node.hidden ? 0 : top(anchor.node) - offset
  }

  function describe(facts: Awaited<ReturnType<typeof ovvi.git.show>> | undefined) {
    about.replaceChildren()
    document.title = facts?.subject ?? ""
    if (!facts) return
    const date = new Date(facts.date), list = element("dl")
    const fact = (term: string, ...value: (Node | string)[]) => {
      const line = element("dd")
      line.append(...value)
      list.append(element("dt", "", term), line)
    }
    fact("Author", facts.author, element("span", "dim", ` <${facts.email}>`))
    fact("Date", ago(date), element("span", "dim", ` · ${date.toLocaleString(undefined, { dateStyle: "medium", timeStyle: "short" })}`))
    const copy = element("button", "hash", facts.hash.slice(0, 10))
    copy.title = "Copy"
    copy.ariaLabel = `Copy ${facts.hash}`
    copy.onclick = () => ovvi.clipboard.write(facts.hash).then(() => {
      copy.textContent = "Copied"
      setTimeout(() => (copy.textContent = facts.hash.slice(0, 10)), 1200)
    }, toast)
    fact("Commit", copy)
    if (facts.parents.length) {
      fact(facts.parents.length > 1 ? "Parents" : "Parent", ...facts.parents.map((parent) => {
        const button = element("button", "hash", parent.slice(0, 10))
        button.ariaLabel = `Parent ${parent}`
        button.onclick = (event) => open(`${home(root)} ${parent}`, { how: how(event, false), plugin: "git" })
        button.oncontextmenu = (event) => void menu(event, `${home(root)} ${parent}`, { plugin: "git" })
        return button
      }))
    }
    about.append(element("h1", "", facts.subject), ...(facts.body ? [element("p", "body", facts.body)] : []), list)
  }

  function draw(next: string) {
    patch = next
    files = parsePatchFiles(patch).flatMap((parsed) => parsed.files)
    steady(() => put(files))
    listFiles(files)
    sift()
  }

  function sift() {
    const shows = (name: string) => name.toLowerCase().includes(filter)
    steady(() => {
      for (const [name, box] of boxes) box.node.hidden = !shows(name)
    })
    for (const node of nav.querySelectorAll<HTMLElement>(".row")) node.hidden = !shows(node.dataset.id!)
    const kept = files.filter((file) => shows(file.name))
    count.textContent = filter ? String(kept.length) : ""
    changes = kept.flatMap(blocks)
    shown(files.length > 0 && !kept.length)
  }

  function put(files: FileDiffMetadata[]) {
    const was = boxes, drawn: Box[] = []
    boxes = new Map()
    for (const file of files) {
      let box = was.get(file.name)
      was.delete(file.name)
      if (!box) {
        const { added, removed } = sums(file), node = element("section", "box")
        node.hidden = !file.name.toLowerCase().includes(filter)
        box = { diff: file, node, row: node, lines: document.createElement("diffs-container"), folded: added + removed > 2000 }
        owners.set(node, box)
        nearby.observe(node)
      } else if (text(box.diff) !== text(file) || box.diff.type !== file.type || box.diff.prevName !== file.prevName) {
        box.diff = file
        if (viewed.delete(file.name)) box.folded = false
        drawn.push(box)
      } else {
        boxes.set(file.name, box)
        continue
      }
      box.row = fileRow(box)
      box.node.replaceChildren(box.row, box.lines)
      boxes.set(file.name, box)
    }
    for (const [name, box] of was) {
      viewed.delete(name)
      nearby.unobserve(box.node)
      box.view?.cleanUp()
    }
    // Moved only when the order changed: a move lays the box out again.
    const order = [about, ...[...boxes.values()].map((box) => box.node)]
    if (order.some((node, index) => content.children[index] !== node) || content.children.length !== order.length) {
      content.replaceChildren(...order)
    }
    // Once in place: a file's lines draw by where its box sits.
    for (const box of boxes.values()) show(box)
    const { top: from, bottom: to } = main.getBoundingClientRect()
    const near = [...boxes.values()].filter((box) => {
      const { top, bottom } = box.node.getBoundingClientRect()
      return !box.near && bottom > from - MARGIN && top < to + MARGIN
    })
    for (const box of near) {
      box.near = true
      show(box)
    }
    for (const box of drawn) box.view?.render({ fileDiff: box.diff, fileContainer: box.lines })
  }

  function listFiles(files: FileDiffMetadata[]) {
    const title = element("header", "title")
    title.append(element("h2", "", "Files"), element("span", "count", files.length ? String(files.length) : ""))
    nav.replaceChildren(title)
    for (const file of files) {
      const button = element("button", viewed.has(file.name) ? "row viewed" : "row")
      button.dataset.id = file.name
      const [name, folder] = nameAndFolder(file.name)
      button.append(
        fileIcon(file.name),
        element("span", "name", name),
        element("span", "folder", folder),
        ...counts(file),
        letter(file),
      )
      button.title = file.name
      button.ariaLabel = file.name
      button.onclick = () => reveal(file.name)
      nav.append(button)
    }
  }

  function shown(none: boolean) {
    nav.hidden = !files.length
    clean.hidden = (Boolean(files.length) || patch === undefined) && !none
    clean.querySelector("h2")!.textContent = none ? "No matching files" : "No changes"
    clean.style.setProperty("--symbol", `var(${sf(none ? "magnifyingglass" : "checkmark.circle")})`)
    listButton()
  }

  /** Its symbol says whether the list shows: with no files, none does. */
  function listButton() {
    api.controls.set("diff.file-list", { enabled: files.length > 0, value: list && files.length > 0 })
  }

  function openFile(name: string, line: number | undefined, how: How) {
    open(`${root}/${name}`, { how, at: line ? String(line) : undefined })
  }

  function top(node: HTMLElement) {
    return node.getBoundingClientRect().top - main.getBoundingClientRect().top + main.scrollTop
  }

  let moves = 0
  let stepped = 0
  main.addEventListener("wheel", () => moves++, { passive: true })
  main.addEventListener("pointerdown", () => moves++)

  function where(block: (typeof changes)[number]) {
    const box = boxes.get(block.id)!
    const line = box.folded ? undefined : box.view?.getLinePosition(block.lineNumber, block.side)
    return line ? top(box.lines) + line.top + line.height / 2 : top(box.node)
  }

  /** Wrapped lines take their heights once drawn, a frame later: then once more. */
  function scrollToChange(block: (typeof changes)[number]) {
    const box = boxes.get(block.id)
    if (!box) return
    if (box.folded) collapse(block.id, false)
    box.near = true
    show(box)
    const aim = () => (main.scrollTop = where(block) - main.clientHeight / 2)
    aim()
    // Not after another step or the user's scroll meanwhile (pierre's own fixes of the scroll still aim again).
    const was = { change, moves }
    if (options.overflow === "wrap") {
      afterLayout(() => change === was.change && moves === was.moves && aim())
    }
  }

  function keepChange() {
    if (changes[change]) scrollToChange(changes[change])
  }

  function collapse(id: string, folded: boolean) {
    const box = boxes.get(id)!
    box.folded = folded
    show(box)
    if (folded && top(box.node) < main.scrollTop) main.scrollTop = top(box.node)
  }

  function reveal(id: string) {
    const box = boxes.get(id)!
    if (box.node.hidden) closeFind()
    if (box.folded) collapse(id, false)
    main.scrollTop = top(box.node)
    const order = (name: string) => files.findIndex((file) => file.name === name)
    const next = changes.findIndex((block) => order(block.id) >= order(id))
    change = (next < 0 ? changes.length : next) - 0.5
    stepped = moves
  }

  api.on("theme", (theme) => {
    options.themeType = theme.dark ? "dark" : "light"
    for (const box of boxes.values()) box.view?.setThemeType(options.themeType)
  })

  const refresh = coalesce(async () => apply(await read()))

  const read = () => ovvi.git.diff(root, source).catch((error: Error) => error)

  function apply(next: string | Error) {
    if (!(next instanceof Error)) {
      if (next !== patch) draw(next)
    } else if (patch === undefined) failure.textContent = next.message
  }

  /** Side by Side always wraps: a line scrolled past its narrow column is cut off where a click lands. */
  function overflow() {
    return split || wrap ? "wrap" : "scroll"
  }

  function layout(next: { split?: boolean; wrap?: boolean }) {
    split = next.split ?? split
    wrap = next.wrap ?? wrap
    api.controls.set("diff.wrap", { enabled: !split })
    options.diffStyle = split ? "split" : "unified"
    options.overflow = overflow()
    steady(() => {
      for (const box of boxes.values()) {
        if (box.view) box.view.setOptions(fileOptions(box))
        else show(box)
      }
    })
    // Once the files have their new heights: pierre lays them out on the next frame.
    afterLayout(keepChange)
  }

  function toggleList(chosen = true) {
    list = !list
    nav.toggleAttribute("data-closed", !list)
    if (chosen) keep({ list })
    listButton()
    // With Reduce Motion there is no slide to wait for.
    if (matchMedia("(prefers-reduced-motion: reduce)").matches) afterLayout(keepChange)
  }
  // After the slide: once, not for each of its properties.
  nav.addEventListener("transitionend", (event) => event.target === nav && event.propertyName === "visibility" && keepChange())

  function step(by: 1 | -1) {
    if (!changes.length) return
    const view = main.scrollTop + 32, at = changes[change] ? where(changes[change]) : -1
    if (stepped !== moves && (at <= view || at >= main.scrollTop + main.clientHeight)) {
      const below = changes.findIndex((block) => where(block) > view)
      change = (below < 0 ? changes.length : below) - 0.5
    }
    stepped = moves
    const next = by > 0 ? Math.floor(change) + 1 : Math.ceil(change) - 1
    change = Math.min(Math.max(next, 0), changes.length - 1)
    scrollToChange(changes[change])
  }

  function stepFile(by: 1 | -1) {
    // At the end: the files left all show, and a reveal could not move the view.
    if (by > 0 && main.scrollTop >= main.scrollHeight - main.clientHeight - 1) return
    const tops = [...boxes].filter(([, box]) => !box.node.hidden).map(([id, box]) => ({ id, at: top(box.node) }))
    const to = by > 0 ? tops.find(({ at }) => at > main.scrollTop + 1) : tops.findLast(({ at }) => at < main.scrollTop - 1)
    if (to) reveal(to.id)
  }

  api.on("control", ({ id, value }) => {
    if (id === "diff.home") ovvi.card.go(home(root))
    else if (id === "diff.layout") {
      keep({ layout: String(value) })
      layout({ split: value === "split" })
    } else if (id === "diff.wrap") {
      keep({ wrap: value === true })
      layout({ wrap: value === true })
    } else if (id === "diff.file-list") toggleList()
    else if (id === "diff.previous") step(-1)
    else if (id === "diff.next") step(1)
  })

  api.on("findNext", () => step(1))
  api.on("findPrevious", () => step(-1))
  api.on("find", () => {
    find.hidden = false
    field.select()
    field.focus()
  })
  function closeFind() {
    find.hidden = true
    field.value = ""
    field.blur()
    filtered()
  }
  function filtered() {
    if (filter === field.value.toLowerCase()) return
    filter = field.value.toLowerCase()
    change = -1
    stepped = -1
    sift()
  }
  field.oninput = filtered
  field.onkeydown = (event) => {
    if (event.key === "Escape") closeFind()
    else if (event.key === "Enter") field.blur()
    else return
    event.preventDefault()
  }
  find.querySelector("button")!.onclick = closeFind
  const keys = (event: KeyboardEvent) => {
    if (!place.shown || event.metaKey || event.ctrlKey || event.target === field) return
    if (event.key === "]") step(1)
    else if (event.key === "[") step(-1)
    else if (event.key === "}") stepFile(1)
    else if (event.key === "{") stepFile(-1)
    else if (event.key === "Escape" && !find.hidden) closeFind()
    else return
    event.preventDefault()
  }
  document.addEventListener("keydown", keys)
  place.keep(() => document.removeEventListener("keydown", keys))
  // Only the working tree changes.
  api.files.watch(root, () => (source === "uncommitted" || patch === undefined) && void refresh())
  listButton()
  api.controls.set("diff.wrap", { enabled: !split, value: wrap })
  api.controls.set("diff.layout", { value: split ? "split" : "unified" })
  api.on("settings", (changed) => {
    const own = kept()
    if ("diff-layout" in changed && own.layout === undefined) {
      api.controls.set("diff.layout", { value: String(changed["diff-layout"]) })
      layout({ split: changed["diff-layout"] === "split" })
    }
    if ("wrap" in changed && own.wrap === undefined) {
      api.controls.set("diff.wrap", { value: changed.wrap === true })
      layout({ wrap: changed.wrap === true })
    }
    if ("file-list" in changed && own.list === undefined && (changed["file-list"] === true) !== list) toggleList(false)
  })
  // Read first, then draw all of it in one go: the shown page stays until then. The themes first too: a file takes its
  // height only once they are in.
  const [next, facts] = await Promise.all([read(), source === "uncommitted"
    ? undefined
    : ovvi.git.show(root, source).catch(() => undefined),
  preloadHighlighter({ themes: [...new Set(Object.values(options.theme!))], langs: [] }).catch(console.error)])
  describe(facts)
  apply(next)
  if (place.at && files.some((file) => file.name === place.at)) reveal(place.at)
  api.on("place", ({ at }) => at && files.some((file) => file.name === at) && reveal(at))
}
