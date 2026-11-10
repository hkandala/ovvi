import { markdown, markdownLanguage } from "@codemirror/lang-markdown"
import { yamlFrontmatter } from "@codemirror/lang-yaml"
import { ensureSyntaxTree, syntaxTree, syntaxTreeAvailable } from "@codemirror/language"
import { closeSearchPanel } from "@codemirror/search"
import { Compartment, EditorState, Prec } from "@codemirror/state"
import { EditorView } from "@codemirror/view"
import { code, type Editor, editor, selected } from "./editor"
import { containers, editing, live, referenceField, ticked } from "./live"
import { choose, fileURL, how, htmlPage, menu, open, own, type Place, type Reveal, symbols } from "./place"
import { sideBySide } from "./split"

type Mode = "rich" | "source"
type Look = { mode: Mode; locked: boolean; preview: boolean }
const mode = (value: unknown): Mode | undefined => (value === "rich" || value === "source" ? value : undefined)
let cardLook: Look | undefined

/** As GitHub makes a heading's anchor. */
const slug = (text: string) => text.trim().toLowerCase().replace(/[^\p{L}\p{N}\s_-]/gu, "").replace(/\s/g, "-")

/** Not read only: read only is the file's, and a tick while locked writes. */
const markdownMode = (edit: boolean) => [
  EditorView.editable.of(edit),
  edit ? [] : [
    Prec.highest(EditorView.contentAttributes.of({ role: "article", "aria-readonly": "true" })),
    EditorView.domEventHandlers({ drop: (event) => (event.preventDefault(), true) }),
  ],
]
const modeClass = EditorView.editorAttributes.compute([EditorView.editable], (state) => ({
  class: editing(state) ? "" : "cm-reading",
}))
const rendered = [
  live,
  modeClass,
  Prec.highest(EditorView.theme({
    "&": { fontSize: "calc(var(--font-size) + 1px)" },
    ".cm-scroller": { fontFamily: "system-ui", lineHeight: "1.55", outline: "none" },
    ".cm-content": { boxSizing: "border-box", maxWidth: "640px", margin: "0 auto", padding: "28px 24px 48px" },
    "&.cm-reading .cm-activeLine": { background: "none" },
    ".cm-frontmatter, .cm-frontmatter *": {
      fontFamily: "ui-monospace, monospace", fontSize: "12px", color: "var(--dim)",
    },
  })),
]
function headings(state: EditorState, tree = syntaxTree(state)) {
  const found: { from: number; level: number; text: string }[] = []
  tree.iterate({
    enter(node) {
      const level = /^(?:ATX|Setext)Heading(\d)$/.exec(node.name)?.[1]
      if (!level) return containers.includes(node.name)
      const line = state.doc.lineAt(node.from)
      const [first, last] = node.node.getChildren("HeaderMark")
      const text = node.name.startsWith("ATX")
        ? state.sliceDoc(first?.to ?? node.from, last?.from ?? node.to)
        : state.sliceDoc(node.from, line.to)
      found.push({ from: line.from, level: Number(level), text: text.trim() || line.text })
      return false
    },
  })
  return found
}

/** The background parse stops past the viewport. */
const all = (state: EditorState) => headings(state, ensureSyntaxTree(state, state.doc.length, 200) ?? undefined)

function copied(view: EditorView) {
  const selection = getSelection(), content = view.contentDOM
  const range = selection && !selection.isCollapsed ? selection.getRangeAt(0) : undefined
  if (range?.intersectsNode(content)) {
    const end = (node: Node, offset: number, outside: number) =>
      content.contains(node) ? view.posAtDOM(node, offset) : outside
    return view.state.sliceDoc(end(range.startContainer, range.startOffset, 0),
      end(range.endContainer, range.endOffset, view.state.doc.length))
  }
  const main = view.state.selection.main
  return main.empty ? undefined : view.state.sliceDoc(main.from, main.to)
}

export async function show(place: Place): Promise<Reveal> {
  const { ovvi, arg, keep, element: root } = place
  const outline = Object.assign(document.createElement("nav"), { className: "ovvi-sidebar" })
  const pane = document.createElement("main")
  outline.hidden = true
  outline.toggleAttribute("data-closed", true)
  root.append(outline, pane)
  const kept = own(ovvi)
  const first: Look = cardLook ?? {
    mode: mode(kept.mode) ?? mode(ovvi.settings.get("markdown")) ?? "rich",
    locked: kept.locked ?? ovvi.settings.get<boolean>("markdown-lock") !== false,
    preview: kept.preview ?? false,
  }
  /** The editor starts as Rich Text, locked. */
  let now: Look = { mode: "rich", locked: true, preview: false }
  let outlined = false
  let titled = false
  /** Until the first look draws, the page's own landing or kept top line is still to scroll. */
  let presented = false
  const editable = new Compartment(), look = new Compartment()
  let split: ReturnType<typeof sideBySide> | undefined
  keep(() => split?.destroy())

  function present(view: EditorView, next: Look, nowOutlined: boolean) {
    const effects = []
    if (next.locked !== now.locked) {
      if (next.locked) closeSearchPanel(view)
      effects.push(editable.reconfigure(markdownMode(!next.locked)))
    }
    if (next.mode !== now.mode) {
      effects.push(look.reconfigure(next.mode === "source" ? source : rendered))
      const top = view.lineBlockAtHeight(view.scrollDOM.scrollTop - view.documentPadding.top).from
      if (presented) effects.push(EditorView.scrollIntoView(top, { y: "start" }))
    }
    const selection = next.locked ? { anchor: view.state.selection.main.head } : undefined
    if (effects.length) view.dispatch({ selection, effects })
    if (next.mode !== now.mode || (split && next.preview !== now.preview)) {
      split?.destroy()
      split = next.mode === "source" ? sideBySide(view, pane, page, next.preview, folded) : undefined
    }
    now = cardLook = next
    presented = true
    outlined = nowOutlined && titled
    outline.hidden = false
    outline.toggleAttribute("data-closed", !outlined)
    if (outlined) list(view, all(view.state))
    focus(view)
    ovvi.controls.set("mode", { value: next.mode })
    ovvi.controls.set("lock", { value: !next.locked, title: next.locked ? "Edit" : "Stop Editing" })
    ovvi.controls.set("outline", { value: outlined })
    ovvi.controls.set("lock-editing", { enabled: true, checked: next.locked })
  }

  function folded(preview: boolean) {
    now = cardLook = { ...now, preview }
    choose(ovvi, { preview })
  }

  function change(view: EditorView, to: Partial<Look>) {
    choose(ovvi, to)
    present(view, { ...now, ...to }, outlined)
  }

  function focus(view: EditorView) {
    if (!now.locked) view.focus()
    else view.scrollDOM.focus({ preventScroll: true })
  }

  function titles(view: EditorView, found: ReturnType<typeof headings>) {
    if (found.length > 0 !== titled) {
      titled = found.length > 0
      ovvi.controls.set("outline", { hidden: !titled })
      if (!titled && outlined) present(view, now, false)
    }
    if (outlined) list(view, found)
  }

  function list(view: EditorView, found: ReturnType<typeof headings>) {
    outline.replaceChildren(...found.map((heading) => {
      const row = document.createElement("button")
      row.textContent = heading.text
      row.style.paddingLeft = `${12 * heading.level}px`
      row.onclick = () => {
        const effects = EditorView.scrollIntoView(heading.from, { y: "start" })
        view.dispatch(!now.locked ? { selection: { anchor: heading.from }, effects } : { effects })
        focus(view)
      }
      return row
    }))
  }

  function address(link: Element) {
    const target = link.getAttribute("href") ?? ""
    if (/^https?:/i.test(target)) return target
    if (!target || target.startsWith("#") || /^[a-z][a-z\d+.-]*:/i.test(target)) return undefined
    return decodeURIComponent(new URL(target, fileURL(arg)).pathname)
  }

  function html(link: Element, to: string) {
    const page = htmlPage(ovvi, to)
    return page && page + (/[?#].*$/.exec(link.getAttribute("href") ?? "")?.[0] ?? "")
  }

  function linked(view: EditorView, link: Element) {
    if (!editing(view.state)) return true
    const { doc, selection } = view.state
    const from = view.posAtDOM(link), to = view.posAtDOM(link, link.childNodes.length)
    return !selection.ranges.some((range) => doc.lineAt(range.from).from <= to && doc.lineAt(range.to).to >= from)
  }

  function follow(view: EditorView, event: MouseEvent) {
    const link = (event.target as Element).closest("a")
    if (!link) return false
    // Unlocked too: a table's `href=""` link would load the page again and lose the edits.
    event.preventDefault()
    if (!linked(view, link)) return false
    const target = link.getAttribute("href") ?? ""
    if (target.startsWith("#")) {
      let anchor = target.slice(1)
      try {
        anchor = decodeURIComponent(anchor)
      } catch {
        // A `%` with no hex after it: the anchor as written.
      }
      // GitHub adds `-1` to the anchor of a second heading of a name.
      const note = anchor.startsWith("fn:") ? view.state.field(referenceField).notes.get(anchor.slice(3)) : undefined
      const seen = new Map<string, number>()
      const heading = note ?? all(view.state).find((each) => {
        const base = slug(each.text), n = seen.get(base) ?? 0
        seen.set(base, n + 1)
        return (n ? `${base}-${n}` : base) === anchor.toLowerCase()
      })
      if (heading) view.dispatch({ effects: EditorView.scrollIntoView(heading.from, { y: "start" }) })
    } else {
      const to = address(link), page = to ? html(link, to) : undefined
      if (to) open(ovvi, page ?? to, how(event), page ? "browser" : undefined)
    }
    return true
  }

  ovvi.controls.set("mode", { value: first.mode })
  ovvi.controls.set("outline", { value: false })
  ovvi.controls.set("lock-editing", { enabled: true, checked: first.locked })
  symbols(ovvi, ["chevron.left", "chevron.right"])
  let shown: Editor
  /** One after the other: a save under way skips a second one. */
  let ticks = Promise.resolve()
  // Front matter as YAML, not as a rule and a heading.
  const language = yamlFrontmatter({ content: markdown({ base: markdownLanguage }) })
  const links = EditorView.domEventHandlers({
    click: (event, view) => follow(view, event),
    // No caret first: it shows the link's source.
    mousedown: (event, view) => {
      const link = (event.target as Element).closest("a")
      if (!link || event.button || event.shiftKey || !editing(view.state) || !linked(view, link)) return false
      event.preventDefault()
      return true
    },
    contextmenu: (event) => {
      const link = (event.target as Element).closest("a"), to = link && address(link)
      if (!to) return false
      const page = html(link, to)
      void menu(ovvi, event, page ?? to, { link: to, plugin: page ? "browser" : undefined })
      return true
    },
  })
  const source = [code, Prec.highest(EditorView.theme({ ".cm-content": { paddingBottom: "48px" } }))]
  const page = [language, rendered, selected, markdownMode(false), EditorView.lineWrapping, links]
  shown = await editor(place, [
    language,
    look.of(rendered),
    editable.of(markdownMode(false)),
    EditorView.lineWrapping,
    links,
    EditorView.updateListener.of((update) => {
      split?.follow(update)
      if (now.locked && update.transactions.some((tr) => tr.annotation(ticked))) {
        ticks = ticks.then(() => shown?.save())
      }
      // Also as the background parse reaches more headings.
      if (update.docChanged || syntaxTree(update.startState) !== syntaxTree(update.state)) {
        const found = headings(update.state)
        // No heading in a tree cut short says nothing: its headings can be below the parsed part.
        if (found.length || syntaxTreeAvailable(update.state)) titles(update.view, found)
      }
    }),
  ], pane)

  if (!shown) {
    ovvi.controls.set("lock-editing", { enabled: false })
    ovvi.controls.set("mode", { hidden: true })
    ovvi.controls.set("lock", { hidden: true })
    return undefined
  }
  const { view, land } = shown
  // The source of the selection, also of lines not drawn: Select All's selection reaches past the editor.
  const copy = (event: ClipboardEvent) => {
    const mine = view.scrollDOM.contains(document.activeElement)
    const text = !now.locked || !mine || event.defaultPrevented || !place.shown ? undefined : copied(view)
    if (text === undefined) return
    event.clipboardData?.setData("text/plain", text)
    event.preventDefault()
  }
  document.addEventListener("copy", copy)
  keep(() => document.removeEventListener("copy", copy))
  // WebKit's Select All, of the whole page, starts at the line numbers or the outline and ends in Source's page.
  const selectAll = (event: Event) => {
    if (!now.locked || !place.shown || event.target !== document.body) return
    if (!view.scrollDOM.contains(document.activeElement)) return
    event.preventDefault()
    view.dispatch({ selection: { anchor: 0, head: view.state.doc.length } })
  }
  document.addEventListener("selectstart", selectAll)
  keep(() => document.removeEventListener("selectstart", selectAll))
  ovvi.on("control", ({ id, value }) => {
    if (id === "outline") present(view, now, value === true)
    if (id === "mode" && mode(value)) change(view, { mode: mode(value) })
    if (id === "lock") change(view, { locked: value !== true })
    if (id === "lock-editing") change(view, { locked: !now.locked })
  })
  ovvi.on("settings", (changed) => {
    const next = mode(changed.markdown), locked = changed["markdown-lock"], choices = own(ovvi)
    if (next && choices.mode === undefined) present(view, { ...now, mode: next }, outlined)
    if (typeof locked === "boolean" && choices.locked === undefined) present(view, { ...now, locked }, outlined)
  })
  titles(view, all(view.state))
  present(view, first, false)
  ovvi.on("place", () => cardLook && present(view, cardLook, outlined))
  // After the editor's own handler: a locked page takes the keyboard.
  const take = () => place.shown && focus(view)
  addEventListener("focus", take)
  keep(() => removeEventListener("focus", take))
  return land
}
