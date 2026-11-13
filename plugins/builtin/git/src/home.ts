import type { Change, Commit, Page } from "@ovvi/plugin-api"
import { coalesce, copyButton, element, failed, fileIcon, home, how, keep, kept, menu, nameAndFolder, open, ovvi, symbol } from "./lib"

const WORDS: Record<string, string> = {
  M: "Modified", T: "Type changed", A: "Added", D: "Deleted", R: "Renamed", U: "Untracked", C: "Conflict",
}

const LANE = 14, HEIGHT = 28
const COLORS = ["var(--accent)", "var(--finished)", "var(--working)", "var(--needs-you)", "var(--error)"]
const color = (lane: number) => COLORS[lane % COLORS.length]
const x = (lane: number) => 9 + lane * LANE

/** A commit's age: now, 5m, 3h, 2d up to 5 days, then the day, with its year when that is not this one. */
function when(ms: number) {
  const minutes = Math.floor((Date.now() - ms) / 60_000), date = new Date(ms)
  // A clock a minute ahead still reads now; further ahead, the day.
  if (minutes >= -1) {
    if (minutes < 1) return "now"
    if (minutes < 60) return `${minutes}m`
    if (minutes < 24 * 60) return `${Math.floor(minutes / 60)}h`
    if (minutes < 6 * 24 * 60) return `${Math.floor(minutes / (24 * 60))}d`
  }
  const year = date.getFullYear() === new Date().getFullYear() ? undefined : "numeric"
  return date.toLocaleDateString(undefined, { year, month: "short", day: "numeric" })
}

/** Fri, Nov 13, 2026 at 11:20:52 AM */
function stamp(ms: number) {
  const date = new Date(ms)
  const day = date.toLocaleDateString(undefined, { weekday: "short", year: "numeric", month: "short", day: "numeric" })
  return `${day} at ${date.toLocaleTimeString(undefined, { hour: "numeric", minute: "2-digit", second: "2-digit" })}`
}

export async function make(place: Page, root: string) {
  const api = place.ovvi
  const page = element("div")
  page.id = "home"
  page.innerHTML = `
  <p id="failure" hidden></p>
  <div id="no-repository" class="placeholder" hidden>
    <span class="symbol" style="--symbol: var(--sf-folder-badge-questionmark)"></span>
    <h2>Not a Git repository</h2><p class="path"></p>
    <button id="initialize" type="button">Initialize Repository</button>
  </div>
  <main hidden>
    <div id="clean" class="placeholder" hidden>
      <span class="symbol" style="--symbol: var(--sf-checkmark-circle)"></span><h2>No changes</h2>
    </div>
    <div id="changes">
      <form id="commit">
        <textarea id="message" rows="1" placeholder="Message" aria-label="Message"></textarea>
        <button id="commit-button" type="submit" disabled>Commit</button>
      </form>
      <section id="staged"></section>
      <section id="unstaged"></section>
    </div>
    <section id="history"><header class="title"><h2>History</h2></header><div class="rows"></div></section>
  </main>`
  place.element.append(page)

  const notice = page.querySelector<HTMLElement>("#failure")!
  const noRepository = page.querySelector<HTMLElement>("#no-repository")!
  const initialize = page.querySelector<HTMLButtonElement>("#initialize")!
  const clean = page.querySelector<HTMLElement>("#clean")!
  const changesBox = page.querySelector<HTMLElement>("#changes")!
  const content = page.querySelector("main")!
  const form = page.querySelector<HTMLFormElement>("#commit")!
  const message = page.querySelector<HTMLTextAreaElement>("#message")!
  const commitButton = page.querySelector<HTMLButtonElement>("#commit-button")!

  let staged: Change[] = []
  let unstaged: Change[] = []
  let failure: string | undefined
  let limit = ovvi.settings.get<number>("commits")
  let branches: { name: string; remote: boolean; current: boolean }[] = []
  /** In the order they run: the app runs a card's writes one at a time. */
  const running: string[] = []
  let drawn = ""

  let history: Commit[] = [], read: { head: string; asked: number } | undefined
  /** Every read takes the changes and the head from one `git status`; the branches and the history only when git's
   *  own files changed, the head moved, after a write or Show More, or after a read that failed. */
  let whole = true
  const changed = coalesce(work)
  const load = () => {
    whole = true
    return changed()
  }

  async function work() {
    const asked = limit, all = whole
    whole = false
    const [changes] = await Promise.allSettled([ovvi.git.changes(root)])
    const head = changes.status === "fulfilled" ? changes.value.head : null
    const key = JSON.stringify(head)
    const again = all || read?.head !== key || read.asked !== asked
    const [list, commits] = again
      ? await Promise.allSettled([ovvi.git.branches(root), ovvi.git.log(root, { limit: asked })])
      : [{ status: "fulfilled", value: branches } as const, { status: "fulfilled", value: history } as const]
    read = changes.status === "fulfilled" && list.status === "fulfilled" && commits.status === "fulfilled"
      ? { head: key, asked } : undefined
    // ponytail: any failure of `git.root` (a folder gone, a repository git refuses) reads as none; match git's message
    // if those must show it.
    const bare = changes.status === "rejected" && (await ovvi.git.root(root).catch(() => "")) === null
    failure = changes.status === "rejected" ? (changes.reason as Error).message : undefined
    branches = list.status === "fulfilled" ? list.value : []
    api.controls.set("git.branch", {
      title: head?.branch ?? "—",
      value: head?.branch ?? "",
      items: [
        ...branches.filter((b) => !b.remote).map((b) => ({ value: b.name, title: b.name })),
        ...(branches.some((b) => b.remote)
          ? ["-" as const, { title: "Remote" }, ...branches.filter((b) => b.remote).map((b) => ({ value: b.name, title: b.name }))]
          : []),
      ],
    })
    const count = (n: number, word: string) => (n > 0 ? { badge: n, label: `${word}, ${n} ${word === "Pull" ? "behind" : "ahead"}` }
      : { badge: 0, label: "" })
    api.controls.set("git.pull", count(head?.behind ?? 0, "Pull"))
    api.controls.set("git.push", count(head?.ahead ?? 0, "Push"))
    buttons()
    history = commits.status === "fulfilled" ? commits.value : []
    const state = changes.status === "fulfilled"
      ? { ...changes.value, commits: history, more: history.length >= asked }
      : { failure, bare }
    // A draw under a click loses the click: only a change draws. The app's replies have their keys sorted.
    const json = JSON.stringify(state)
    if (json === drawn) return
    drawn = json
    draw(state)
  }

  function buttons() {
    const off = Boolean(failure || running.length)
    api.controls.set("git.branch", { busy: running[0] === "switch", enabled: branches.length > 0 && !running.length })
    for (const name of ["fetch", "pull", "push"]) api.controls.set(`git.${name}`, { busy: running[0] === name, enabled: !off })
    api.controls.set("git.working", { enabled: !failure })
  }

  function draw(state: {
    staged?: Change[]; unstaged?: Change[]; commits?: Commit[]; more?: boolean; failure?: string; bare?: boolean
  }) {
    noRepository.hidden = !state.bare
    // ponytail: any user's home reads `~`: the plugin API has no home folder.
    noRepository.querySelector(".path")!.textContent = root.replace(/^\/(Users|home)\/[^/]+(?=\/|$)/, "~")
    notice.hidden = !state.failure || Boolean(state.bare)
    notice.textContent = state.failure ?? ""
    content.hidden = Boolean(state.failure)
    if (state.failure) return
    staged = state.staged ?? []
    unstaged = state.unstaged ?? []
    clean.hidden = Boolean(staged.length || unstaged.length)
    changesBox.hidden = !clean.hidden
    section("staged", "Staged Changes", staged, true)
    section("unstaged", "Changes", unstaged, false)
    const commits = state.commits ?? []
    const rows = page.querySelector("#history .rows")!, had = rows.contains(document.activeElement)
    rows.replaceChildren(...(commits.length ? graph(commits) : [element("p", "empty", "No commits yet")]))
    // The selection stays, with no scroll, and takes the keyboard only if it had it: a redraw comes after every write
    // and every change in the work tree.
    const again = page.querySelector<HTMLElement>(`[id="commit.${selected}"]`)
    if (!again) selected = undefined
    again?.classList.add("selected")
    if (had) again?.querySelector<HTMLElement>(".open")!.focus({ preventScroll: true })
    if (state.more) {
      const more = element("button", "more", "Show More")
      more.onclick = () => {
        more.disabled = true
        limit += ovvi.settings.get<number>("commits")
        void load()
      }
      rows.append(more)
    }
    enable()
  }

  function section(id: string, title: string, changes: Change[], staged: boolean) {
    const node = page.querySelector<HTMLElement>(`#${id}`)!
    node.hidden = !changes.length
    const header = element("header", "title")
    header.append(element("h2", "", title), element("span", "count", String(changes.length)))
    const revertAll = element("button", "all", "Revert All")
    revertAll.ariaLabel = `Revert All ${title}`
    const all = element("button", "all", staged ? "Unstage All" : "Stage All")
    revertAll.onclick = () => void revert(changes)
    all.onclick = () => void write(staged ? ovvi.git.unstage(root) : ovvi.git.stage(root))
    header.append(revertAll, all)
    const rows = element("div", "rows")
    rows.append(...changes.map((change) => changeRow(change, staged)))
    node.replaceChildren(header, rows)
  }

  function button(name: string, label: string, action: () => void) {
    const node = element("button", "icon")
    node.title = label
    node.ariaLabel = label
    node.append(symbol(name))
    node.onclick = (event) => {
      event.stopPropagation()
      action()
    }
    return node
  }

  async function write(done: Promise<void>, busy?: string) {
    if (busy) {
      running.push(busy)
      buttons()
    }
    const worked = await done.then(() => true, (error: Error) => {
      void failed(error)
      return false
    })
    if (busy) {
      running.splice(running.indexOf(busy), 1)
      buttons()
    }
    await load()
    return worked
  }

  /** A button in a button is no button to VoiceOver. */
  function row(label: string, arg: string, at?: string) {
    const node = element("div", "row"), button = element("button", "open")
    button.ariaLabel = label
    node.append(button)
    node.onclick = (event) => open(arg, { how: how(event), at, plugin: "git" })
    node.oncontextmenu = (event) => void menu(event, arg, { at, plugin: "git" })
    return { node, open: button }
  }

  function changeRow(change: Change, staged: boolean) {
    const name = change.path.replace(/\/$/, ""), [base, folder] = nameAndFolder(name)
    const diff = `${home(root)} uncommitted`
    const { node, open: face } = row(`${WORDS[change.letter] ?? change.letter}: ${name}`, diff, change.path)
    // ⌘⌥ opens the file itself in the Mac's app; a deleted one has none, so ⌘⌥ is ⌘ there.
    node.onclick = (event) => {
      const by = how(event, change.letter !== "D")
      if (by === "mac") open(`${home(root)}${change.path}`, { how: by })
      else open(diff, { how: by, at: change.path, plugin: "git" })
    }
    node.id = `${staged ? "staged" : "change"}.${change.path}`
    node.title = change.oldPath ? `${change.oldPath} → ${name}` : name
    const toggle = staged ? "Unstage" : "Stage", letter = element("span", `letter ${change.letter}`, change.letter)
    // The label says it.
    letter.ariaHidden = "true"
    face.append(fileIcon(name), element("span", "name", base), element("span", "folder", folder))
    node.append(
      button("arrow.uturn.backward", `Revert ${name}`, () => void revert([change])),
      button(staged ? "minus" : "plus", `${toggle} ${name}`, () =>
        write(staged ? ovvi.git.unstage(root, paths(change)) : ovvi.git.stage(root, paths(change)))),
      letter,
    )
    return node
  }

  const paths = (change: Change) => [change.path, ...(change.oldPath ? [change.oldPath] : [])]

  async function revert(changes: Change[]) {
    const added = new Set(staged.filter((change) => change.letter === "A").map((change) => change.path))
    const fresh = changes.filter((change) => change.letter === "U" || added.has(change.path))
      .map((change) => nameAndFolder(change.path)[0])
    const named = fresh.length > 3 ? `${fresh.slice(0, 2).join(", ")} and ${fresh.length - 2} more` : fresh.join(", ")
    const base = nameAndFolder(changes[0].path)[0]
    const deletes = fresh.length ? ` This deletes the new ${fresh.length > 1 ? "files" : "file"} ${named}.` : ""
    const question = changes.length > 1 ? `Revert all ${changes.length} files?${deletes}`
      : fresh.length ? `Delete the new file ${base}?` : `Revert changes to ${base}?`
    const picked = await ovvi.toast(`${question} This cannot be undone.`, ["Cancel", "Revert"], { destructive: true })
    if (picked !== "Revert") return
    await write(ovvi.git.revert(root, changes.flatMap(paths)))
  }

  function graph(commits: Commit[]) {
    const lanes = Math.max(0, ...commits.flatMap(({ lane, children, parents, through }) => [lane, ...children, ...parents, ...through]))
    const width = x(lanes) + 9
    return commits.map((commit) => commitRow(commit, width))
  }

  function commitRow(commit: Commit, width: number) {
    const { hash, subject, date, lane, children, parents, through, refs } = commit
    const mid = HEIGHT / 2
    const line = (from: number, y1: number, to: number, y2: number) =>
      `<path d="M${x(from)} ${y1} C${x(from)} ${mid} ${x(to)} ${mid} ${x(to)} ${y2}" stroke="${color(from === lane ? to : from)}"/>`
    const head = refs.some((ref) => ref === "HEAD" || ref.startsWith("HEAD -> "))
    const dot = head
      ? `<circle cx="${x(lane)}" cy="${mid}" r="4.5" fill="var(--card)" stroke="${color(lane)}" stroke-width="2"/>`
      : `<circle cx="${x(lane)}" cy="${mid}" r="4" fill="${color(lane)}"/>`
    const names = refs.flatMap(badge)
    const label = [subject, ...names.map((name) => name.textContent), commit.author, stamp(date)].join(", ")
    const { node, open } = row(label, `${home(root)} ${hash}`)
    node.id = `commit.${hash}`
    node.classList.add("commit")
    // VoiceOver's press counts no clicks.
    node.onclick = (event) => (how(event) === "card" && event.detail === 1 ? select(node) : openCommit(event, node))
    node.title = subject
    open.insertAdjacentHTML("afterbegin", `<svg width="${width}" height="${HEIGHT}" fill="none" stroke-width="1.5">${[
      ...through.map((at) => line(at, 0, at, HEIGHT)),
      ...children.map((at) => line(at, 0, lane, mid)),
      ...parents.map((at) => line(lane, mid, at, HEIGHT)),
    ].join("")}${dot}</svg>`)
    open.append(...names, element("span", "name", subject), element("span", "author", commit.author))
    // Beside the row's button, not in it: a button in a button is no button to VoiceOver.
    const age = element("span", "when", when(date))
    age.title = stamp(date)
    age.dataset.date = String(date)
    node.append(copyButton(hash, 7), age)
    return node
  }

  let selected: string | undefined

  function select(node: HTMLElement | null) {
    page.querySelector(".commit.selected")?.classList.remove("selected")
    selected = node?.id.slice("commit.".length)
    if (!node) return
    node.classList.add("selected")
    node.querySelector<HTMLElement>(".open")!.focus()
    node.scrollIntoView({ block: "nearest" })
  }

  function openCommit(event: MouseEvent | KeyboardEvent, node: HTMLElement) {
    open(`${home(root)} ${node.id.slice("commit.".length)}`, { how: how(event, false), plugin: "git" })
  }

  page.addEventListener("click", (event) => {
    if (!(event.target as Element).closest(".commit")) select(null)
  }, true)
  page.addEventListener("pointerdown", () => page.removeAttribute("data-keys"), true)
  const keys = (event: KeyboardEvent) => {
    const target = event.target as Element
    if (!place.shown || content.hidden || event.metaKey || event.ctrlKey || event.altKey || event.shiftKey
      || target.closest("textarea, input")) return
    const rows = [...page.querySelectorAll<HTMLElement>(".commit")], at = rows.findIndex((row) => row.id === `commit.${selected}`)
    if (event.key === "Enter" && at >= 0 && (target === document.body || target.closest(".commit.selected .open"))) {
      openCommit(event, rows[at])
    } else if (event.key === "ArrowDown" || event.key === "ArrowUp") {
      const down = event.key === "ArrowDown"
      const next = at < 0 ? (down ? 0 : rows.length - 1) : Math.min(Math.max(at + (down ? 1 : -1), 0), rows.length - 1)
      if (!rows[next]) return
      page.setAttribute("data-keys", "")
      select(rows[next])
    } else return
    event.preventDefault()
  }
  document.addEventListener("keydown", keys)
  // The ages move on with no draw of the rows: a draw under a click loses the click.
  const ages = setInterval(() => {
    for (const node of page.querySelectorAll<HTMLElement>(".commit .when")) {
      const text = when(Number(node.dataset.date))
      if (node.textContent !== text) node.textContent = text
    }
  }, 60_000)
  place.keep(() => {
    document.removeEventListener("keydown", keys)
    clearInterval(ages)
  })

  function badge(ref: string) {
    const head = ref.startsWith("HEAD -> "), full = head ? ref.slice(8) : ref
    const kinds: [string, string][] = [["refs/heads/", "source.branch"], ["refs/remotes/", "cloud"], ["tag: refs/tags/", "tag"]]
    const kind = kinds.find(([prefix]) => full.startsWith(prefix))
    // `origin/HEAD` names another one; a detached HEAD is `HEAD`.
    if (full.endsWith("/HEAD") || (!kind && full !== "HEAD")) return []
    const node = element("span", head || full === "HEAD" ? "badge head" : "badge")
    node.append(symbol(kind?.[1] ?? "source.branch"), element("span", "", kind ? full.slice(kind[0].length) : "HEAD"))
    return [node]
  }

  api.on("settings", ({ commits }) => {
    if (typeof commits !== "number") return
    limit = commits
    void load()
  })
  api.on("control", ({ id, value }) => {
    if (id === "git.working") ovvi.card.go(`${home(root)} uncommitted`)
    else if (id === "git.branch") {
      const branch = branches.find((branch) => branch.name === value)
      if (branch && !branch.current) void write(ovvi.git.switch(root, branch.name), "switch")
    } else if (id === "git.fetch") void write(ovvi.git.fetch(root), "fetch")
    else if (id === "git.pull") void write(ovvi.git.pull(root), "pull")
    else if (id === "git.push") void write(ovvi.git.push(root), "push")
  })

  initialize.onclick = () => {
    initialize.disabled = true
    void write(ovvi.git.init(root)).then(() => (initialize.disabled = false))
  }

  let committing = false
  function enable() {
    commitButton.textContent = staged.length ? "Commit" : "Commit All"
    commitButton.disabled = committing || !message.value.trim() || !(staged.length || unstaged.length)
  }
  function grow() {
    message.style.height = "auto"
    message.style.height = `${message.scrollHeight}px`
  }
  message.addEventListener("input", () => {
    grow()
    enable()
    keep({ draft: message.value })
  })
  message.addEventListener("keydown", (event) => {
    if (event.key === "Enter" && event.metaKey) {
      event.preventDefault()
      form.requestSubmit()
    }
  })
  form.addEventListener("submit", async (event) => {
    event.preventDefault()
    if (commitButton.disabled) return
    const text = message.value
    committing = true
    enable()
    const done = await write((staged.length ? Promise.resolve() : ovvi.git.stage(root)).then(() => ovvi.git.commit(root, text)),
      "commit")
    committing = false
    // Not a message typed meanwhile.
    if (done && message.value === text) {
      message.value = ""
      message.style.height = "auto"
      keep({ draft: "" })
    }
    enable()
  })

  api.files.watch(root, () => void changed())
  api.git.watch(root, () => void load())
  message.value = kept().draft ?? ""
  await load()
  document.title = ""
  // Once its form shows: hidden, it has no height.
  if (message.value) grow()
  const at = place.at ?? "", ids = at.startsWith(`${home(root)} `) ? [`commit.${at.split(" ").pop()}`]
    : [`change.${at}`, `staged.${at}`]
  if (at) [...page.querySelectorAll("[id]")].find((node) => ids.includes(node.id))?.scrollIntoView({ block: "center" })
}
