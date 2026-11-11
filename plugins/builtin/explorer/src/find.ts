import {
  closeSearchPanel,
  findNext,
  findPrevious,
  getSearchQuery,
  openSearchPanel,
  replaceAll,
  replaceNext,
  SearchQuery,
  setSearchQuery,
} from "@codemirror/search"
import type { EditorState } from "@codemirror/state"
import { EditorView, type Panel, type ViewUpdate } from "@codemirror/view"
import type { Ovvi } from "@ovvi/plugin-api"
import { sf, symbols } from "./place"

type Flag = "caseSensitive" | "wholeWord" | "regexp"
const FLAGS: [Flag, string, string][] = [
  ["caseSensitive", "textformat", "Match Case"],
  ["wholeWord", "textformat.abc.dottedunderline", "Whole Word"],
  ["regexp", "asterisk", "Regular Expression"],
]
/** Counting stops here: a count of every match of a short query in a big file would cost each keystroke. */
const MOST = 1000

function count(state: EditorState, query: SearchQuery) {
  if (!query.search) return ""
  if (!query.valid) return "Invalid"
  const { from, to } = state.selection.main, cursor = query.getCursor(state)
  let n = 0, at = 0
  for (let next = cursor.next(); !next.done && n < MOST; next = cursor.next()) {
    n++
    if (next.value.from === from && next.value.to === to) at = n
  }
  return `${at} of ${n < MOST ? n : `${MOST}+`}`
}

const make = <K extends keyof HTMLElementTagNameMap>(tag: K, props: object) =>
  Object.assign(document.createElement(tag), props)

function icon(symbol: string, title: string, onclick: () => void) {
  const button = make("button", { type: "button", className: "find-icon", title, ariaLabel: title, onclick })
  button.style.setProperty("--symbol", `var(${sf(symbol)})`)
  return button
}

export function finder(ovvi: Ovvi) {
  let shown: ((replace: boolean) => void) | undefined

  function createPanel(view: EditorView): Panel {
    symbols(ovvi, ["chevron.up", "chevron.down", "xmark", ...FLAGS.map(([, symbol]) => symbol)])
    // `name="search"`: WebKit tells VoiceOver it is a search field. No spellcheck: with it, the Mac's text checking
    // corrects and capitalizes code typed in the fields (`w = 5` became `W = 5`).
    const field = make("input", { name: "search", className: "find-field", placeholder: "Find", ariaLabel: "Find",
      spellcheck: false })
    const swap = make("input", { name: "replace", className: "find-field", placeholder: "Replace",
      ariaLabel: "Replace", spellcheck: false })
    field.setAttribute("main-field", "true")
    const counted = make("span", { className: "find-count", role: "status" })
    const toggles = FLAGS.map(([flag, symbol, title]) =>
      icon(symbol, title, () => commit({ [flag]: !getSearchQuery(view.state)[flag] })))
    const run = (command: (view: EditorView) => boolean) => () => void command(view)
    const button = (textContent: string, title: string, command: (view: EditorView) => boolean) =>
      make("button", { type: "button", className: "find-button", textContent, title, ariaLabel: title,
        onclick: run(command) })
    const findRow = make("div", { className: "find-row" }), replaceRow = make("div", { className: "find-row" })
    /** A locked page's text takes no keyboard: its scroller does, so the keys scroll it. */
    const close = () => {
      closeSearchPanel(view)
      if (view.state.facet(EditorView.editable)) view.focus()
      else view.scrollDOM.focus({ preventScroll: true })
    }
    findRow.append(field, counted, ...toggles, icon("chevron.up", "Find Previous", run(findPrevious)),
      icon("chevron.down", "Find Next", run(findNext)), icon("xmark", "Close", close))
    replaceRow.append(swap, button("Replace", "Replace", replaceNext), button("All", "Replace All", replaceAll))
    const dom = make("div", { className: "find" })
    dom.append(findRow, replaceRow)

    function commit(change: Partial<Record<Flag, boolean>> = {}) {
      const old = getSearchQuery(view.state)
      const query = new SearchQuery({ ...old, search: field.value, replace: swap.value, ...change })
      if (!query.eq(old)) view.dispatch({ effects: setSearchQuery.of(query) })
    }
    function draw(state: EditorState) {
      const query = getSearchQuery(state)
      if (field.value !== query.search) field.value = query.search
      if (swap.value !== query.replace) swap.value = query.replace
      FLAGS.forEach(([flag], index) => (toggles[index].ariaPressed = String(query[flag])))
      counted.textContent = count(state, query)
    }
    function show(replace: boolean) {
      replaceRow.hidden = !replace || view.state.readOnly || !view.state.facet(EditorView.editable)
      ;(replaceRow.hidden ? field : swap).select()
    }

    swap.oninput = () => commit()
    // WebKit gives a clicked button no focus: the keyboard leaves the field for the page unless the press is stopped.
    dom.onmousedown = (event) => (event.target as Element).closest("button") && event.preventDefault()
    // Not `findNext`: it selects the field's text, and the next letter would replace it.
    field.oninput = () => {
      commit()
      const query = getSearchQuery(view.state), state = view.state
      if (!query.valid) return
      const after = query.getCursor(state, state.selection.main.from).next()
      const match = after.done ? query.getCursor(state).next() : after
      if (match.done) return
      view.dispatch({ selection: { anchor: match.value.from, head: match.value.to }, scrollIntoView: true })
    }
    dom.onkeydown = (event) => {
      if (event.key === "Escape") {
        event.preventDefault()
        close()
      } else if (event.key === "Enter" && event.target === field) {
        event.preventDefault()
        ;(event.shiftKey ? findPrevious : findNext)(view)
      } else if (event.key === "Enter" && event.target === swap) {
        event.preventDefault()
        ;(event.metaKey ? replaceAll : replaceNext)(view)
      }
    }
    draw(view.state)
    replaceRow.hidden = true
    return {
      dom,
      top: true,
      mount() {
        shown = show
        field.select()
      },
      update(update: ViewUpdate) {
        if (update.docChanged || update.selectionSet || update.transactions.some((tr) =>
          tr.effects.some((effect) => effect.is(setSearchQuery)))) draw(update.state)
      },
      destroy() {
        shown = undefined
      },
    }
  }

  function open(view: EditorView, replace: boolean) {
    openSearchPanel(view)
    shown?.(replace)
  }
  return { createPanel, open }
}
