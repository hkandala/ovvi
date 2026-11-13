import { defaultKeymap, history, historyKeymap, indentWithTab } from "@codemirror/commands"
import {
  bracketMatching,
  ensureSyntaxTree,
  HighlightStyle,
  indentOnInput,
  language,
  syntaxHighlighting,
  syntaxTreeAvailable,
} from "@codemirror/language"
import { findNext, findPrevious, highlightSelectionMatches, search, searchKeymap } from "@codemirror/search"
import { EditorState, type Extension, type Text } from "@codemirror/state"
import {
  drawSelection,
  EditorView,
  highlightActiveLine,
  highlightActiveLineGutter,
  highlightSpecialChars,
  keymap,
  lineNumbers,
  ViewPlugin,
} from "@codemirror/view"
import { tags } from "@lezer/highlight"
import type { OvviError } from "@ovvi/plugin-api"
import { finder } from "./find"
import { failed, info } from "./info"
import { name, type Place } from "./place"

/** CodeMirror parses past the first screen in idle time, on a wall-clock budget (3 s in 30 s) that renews only while
 *  the editor has focus: a page the system paused mid-parse spends it at once, and a card that never takes focus keeps
 *  the lines in view unparsed. */
const parsed = ViewPlugin.fromClass(
  class {
    pending = 0

    constructor(readonly view: EditorView) {
      this.update()
    }

    update() {
      const { state, viewport } = this.view
      if (!this.pending && state.facet(language) && !syntaxTreeAvailable(state, viewport.to)) this.parse()
    }

    parse() {
      this.pending = window.setTimeout(() => {
        if (!ensureSyntaxTree(this.view.state, this.view.viewport.to, 50)) return this.parse()
        this.pending = 0
        // The state takes the tree.
        this.view.dispatch({})
      })
    }

    destroy() {
      clearTimeout(this.pending)
    }
  },
)

const color = (light: string, dark: string) => `light-dark(${light}, ${dark})`

/** @pierre/diffs' default Shiki themes, Pierre Light and Pierre Dark, by the TextMate scope each tag stands for. */
const highlight = HighlightStyle.define([
  { tag: [tags.keyword, tags.modifier, tags.controlKeyword, tags.operatorKeyword], color: color("#d32a61", "#ff678d") },
  { tag: [tags.string, tags.special(tags.string), tags.monospace], color: color("#199f43", "#5ecc71") },
  { tag: tags.regexp, color: color("#17a5af", "#64d1db") },
  { tag: tags.escape, color: color("#16a994", "#61d5c0") },
  { tag: [tags.number, tags.bool, tags.null, tags.atom], color: color("#1ca1c7", "#68cdf2") },
  { tag: [tags.comment, tags.meta, tags.quote], color: "#737373" },
  { tag: [tags.typeName, tags.className], color: color("#a631be", "#d568ea") },
  { tag: [tags.namespace, tags.self, tags.constant(tags.variableName)], color: color("#d5901c", "#ffab16") },
  { tag: [tags.function(tags.variableName), tags.function(tags.propertyName)], color: color("#693acf", "#9d6afb") },
  { tag: [tags.variableName, tags.propertyName], color: color("#d47628", "#ffa359") },
  { tag: [tags.operator, tags.definitionOperator, tags.compareOperator], color: "#08c0ef" },
  { tag: [tags.punctuation, tags.bracket, tags.separator, tags.processingInstruction], color: "#636363" },
  { tag: [tags.tagName, tags.heading], color: color("#d5512f", "#ff855e") },
  { tag: tags.attributeName, color: color("#18a46c", "#60d199") },
  { tag: [tags.annotation, tags.link, tags.url], color: color("#1a85d4", "#69b1ff") },
  { tag: tags.emphasis, fontStyle: "italic" },
  { tag: tags.strong, fontWeight: "bold" },
  { tag: tags.strikethrough, textDecoration: "line-through" },
  { tag: tags.invalid, color: "var(--error)" },
])

export const code = [lineNumbers(), highlightActiveLineGutter(), syntaxHighlighting(highlight)]

const theme = EditorView.theme({
  "&": { height: "100%", fontSize: "var(--font-size)" },
  "&.cm-focused": { outline: "none" },
  ".cm-scroller": { fontFamily: "ui-monospace, monospace", lineHeight: "1.5" },
  ".cm-content": { caretColor: "var(--text)" },
  // CodeMirror draws its own caret, black unless a theme says dark.
  ".cm-cursor, .cm-dropCursor": { borderLeftColor: "var(--text)" },
  ".cm-gutters": { background: "transparent", color: "var(--dim)", border: "none" },
  ".cm-activeLine, .cm-activeLineGutter": { background: "color-mix(in srgb, var(--text) 6%, transparent)" },
  ".cm-searchMatch": { background: "color-mix(in srgb, var(--finished) 35%, transparent)" },
  ".cm-panels.cm-panels-top": {
    position: "absolute", top: "8px", right: "12px", left: "auto", background: "none", border: "none",
    maxWidth: "calc(100% - 24px)",
  },
})

/** As specific as CodeMirror's light selection, which wins otherwise. */
export const selected = EditorView.theme({
  "&.cm-focused > .cm-scroller > .cm-selectionLayer .cm-selectionBackground, .cm-selectionBackground, ::selection": {
    background: "color-mix(in srgb, var(--accent) 35%, transparent)",
  },
})

export type Editor = { view: EditorView; land(at: string | undefined): void; save(): Promise<void> } | undefined

export async function editor(place: Place, extensions: Extension[], parent: HTMLElement): Promise<Editor> {
  const { ovvi, arg: path, keep } = place
  const file = await (place.read ?? ovvi.files.read(path)).catch((error: OvviError) => error)
  if (file instanceof Error) {
    if (file.code === "notText" || file.code === "tooLarge") await info(ovvi, path, parent)
    else failed(file, parent)
    return undefined
  }
  let disk: Text
  let hash = file.hash
  let saving: Text | undefined
  /** So a check that read the disk ahead of a save does not answer after it. */
  let saves = 0
  let dirty = false
  const find = finder(ovvi)

  const update = (state: EditorState) => {
    const now = !state.doc.eq(disk)
    if (now !== dirty) {
      dirty = now
      ovvi.card.setDirty(dirty)
    }
  }

  const view = new EditorView({
    parent,
    state: EditorState.create({
      doc: file.text,
      extensions: [
        file.text.includes("\r\n") ? EditorState.lineSeparator.of("\r\n") : [],
        EditorState.readOnly.of(!file.writable),
        highlightSpecialChars(),
        parsed,
        history(),
        drawSelection(),
        indentOnInput(),
        bracketMatching(),
        highlightActiveLine(),
        highlightSelectionMatches(),
        search({ top: true, createPanel: find.createPanel }),
        keymap.of([...defaultKeymap, ...searchKeymap, ...historyKeymap, indentWithTab]),
        theme,
        selected,
        EditorView.updateListener.of((u) => u.docChanged && update(u.state)),
        extensions,
      ],
    }),
  })
  disk = view.state.doc
  keep(() => {
    view.destroy()
    if (dirty) ovvi.card.setDirty(false)
  })

  /** Only the changed middle is replaced, so the caret and the scroll stay. */
  const load = (text: string, now: string) => {
    hash = now
    // Positions count a line break as one character, whatever the file's.
    const next = view.state.toText(text), old = view.state.doc.toString(), shown = next.toString()
    let from = 0
    while (from < old.length && from < shown.length && old[from] === shown[from]) from++
    let end = 0
    while (end < old.length - from && end < shown.length - from && old.at(-1 - end) === shown.at(-1 - end)) end++
    const reload = view.state.update({
      changes: { from, to: old.length - end, insert: next.slice(from, shown.length - end) },
    })
    // Set ahead of the dispatch, whose update reports dirty against it.
    disk = reload.state.doc
    view.dispatch(reload)
  }

  const read = async () => {
    const now = await ovvi.files.read(path).catch((error: OvviError) => error)
    if (place.dropped) return undefined
    if (now instanceof Error) return void (now.code === "notText" || now.code === "tooLarge" ? place.redraw() : undefined)
    if (now.writable === view.state.readOnly) return void place.redraw()
    return now
  }

  const reload = async () => {
    const now = await read()
    if (now) load(now.text, now.hash)
  }

  /** While a toast is up, a change on disk asks nothing more, so it never takes a save's place. */
  let asking = 0
  const ask = async (text: string, buttons: [string, string]) => {
    asking++
    try {
      return await ovvi.toast(text, buttons)
    } finally {
      asking--
    }
  }

  /** Only edits: a save of the text on disk still wakes every watcher of the file. One at a time: a second would
   *  check the first's stale hash. */
  const save = async (over: string | null = hash) => {
    // After Discard the handlers live until the next place draws.
    if (place.dropped || view.state.readOnly || !dirty || saving) return
    saves++
    const sent = (saving = view.state.doc)
    let failure: OvviError | undefined
    try {
      // In the file's own line breaks.
      hash = (await ovvi.files.write(path, view.state.sliceDoc(), { over: over ?? undefined })).hash
      disk = sent
      if (!place.dropped) update(view.state)
    } catch (error) {
      failure = error as OvviError
    } finally {
      saving = undefined
    }
    if (place.dropped) return
    if (failure?.code === "changed") {
      const picked = await ask(`${name(path)} changed on disk since you opened it.`, ["Overwrite", "Reload"])
      if (picked === "Overwrite") await save(null)
      if (picked === "Reload") await reload()
    } else if (failure) {
      const text = `${name(path)} was not saved: ${failure.message}`
      if ((await ask(text, ["Cancel", "Try Again"])) === "Try Again") await save(over)
    }
  }

  const check = async () => {
    const before = hash, started = saves
    // Not after a save began meanwhile: its own answer (saved, or its toast) is the newer one.
    const stale = () => place.dropped || saving || saves !== started || hash !== before
    const onDisk = await ovvi.files.info(path).catch(() => undefined)
    if (!onDisk || onDisk.hash === before || stale()) return
    if (!dirty) {
      const now = await read()
      if (now && !stale()) load(now.text, now.hash)
      return
    }
    if (asking) return
    // Edits are never dropped without the question, also for a file grown too large or read only.
    const picked = await ask(`${name(path)} changed on disk.`, ["Reload", "Keep Mine"])
    if (place.dropped) return
    if (picked === "Reload") void reload()
    if (picked === "Keep Mine") hash = onDisk.hash
  }

  const land = (at: string | undefined) => {
    const line = Number(at)
    if (!(line >= 1 && line <= view.state.doc.lines)) return
    const pos = view.state.doc.line(line).from
    view.dispatch({ selection: { anchor: pos }, effects: EditorView.scrollIntoView(pos, { y: "center" }) })
  }
  land(place.at)
  // WebKit keeps sessionStorage when the system ends the page's process: the reloaded page shows the same lines.
  const top = `top ${path}`, kept = Number(sessionStorage.getItem(top))
  if (!place.at && kept > 1 && kept <= view.state.doc.lines) {
    view.dispatch({ effects: EditorView.scrollIntoView(view.state.doc.line(kept).from, { y: "start" }) })
  }
  let noting = 0
  view.scrollDOM.addEventListener("scroll", () => {
    clearTimeout(noting)
    noting = window.setTimeout(() => {
      const line = view.lineBlockAtHeight(view.scrollDOM.scrollTop - view.documentPadding.top).from
      sessionStorage.setItem(top, String(view.state.doc.lineAt(line).number))
    }, 200)
  })
  keep(() => clearTimeout(noting))

  ovvi.on("save", () => void save())
  ovvi.on("find", () => find.open(view, false))
  ovvi.on("control", ({ id }) => id === "find-replace" && place.shown && find.open(view, true))
  ovvi.on("findNext", () => findNext(view))
  ovvi.on("findPrevious", () => findPrevious(view))
  ovvi.files.watch(path, () => void check())
  // A change between the read and the watch's start.
  void check()
  const focus = () => place.shown && view.focus()
  addEventListener("focus", focus)
  keep(() => removeEventListener("focus", focus))
  if (document.hasFocus()) view.focus()
  return { view, land, save: () => save() }
}
