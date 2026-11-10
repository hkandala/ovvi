import { Annotation, EditorState, type Extension } from "@codemirror/state"
import { EditorView, type ViewUpdate } from "@codemirror/view"
import { ticked } from "./live"

/** A change one view passed to the other: it goes no further. */
const synced = Annotation.define<boolean>()

function align(from: EditorView, to: EditorView) {
  const at = from.scrollDOM.scrollTop - from.documentPadding.top, block = from.lineBlockAtHeight(at)
  const line = to.lineBlockAt(block.from), into = (at - block.top) / Math.max(block.height, 1)
  to.scrollDOM.scrollTop = line.top + to.documentPadding.top + into * line.height
}

export function sideBySide(source: EditorView, parent: HTMLElement, extensions: Extension, preview: boolean,
  folded: (preview: boolean) => void) {
  const divider = Object.assign(document.createElement("div"), { className: "split-divider" })
  const fold = Object.assign(document.createElement("button"), { type: "button", className: "split-fold" })
  const show = (yes: boolean) => {
    parent.toggleAttribute("data-folded", !yes)
    fold.title = fold.ariaLabel = yes ? "Hide Preview" : "Show Preview"
  }
  show(preview)
  fold.onclick = () => {
    const yes = parent.hasAttribute("data-folded")
    show(yes)
    if (yes) align(source, page)
    folded(yes)
  }
  divider.append(fold)
  parent.append(divider)
  const page: EditorView = new EditorView({
    parent,
    state: EditorState.create({
      doc: source.state.doc,
      // First: the first read only value wins, and the page's locked look says read only.
      extensions: [EditorState.readOnly.of(source.state.readOnly), extensions],
    }),
    dispatchTransactions(transactions, view) {
      view.update(transactions)
      for (const tr of transactions) {
        // A tick stays a tick: a locked source saves it at once.
        const annotations = [synced.of(true), ...(tr.annotation(ticked) ? [ticked.of(true)] : [])]
        if (tr.docChanged && !tr.annotation(synced)) source.dispatch({ changes: tr.changes, annotations })
      }
    },
  })
  // Not by hover: the source scrolls by keys under a pointer resting on the page. The page's own height changes (its
  // widgets measured) never move the source.
  let pageLeads = false
  const input = (event: Event) => {
    const target = event.type === "keydown" ? document.activeElement : event.target
    pageLeads = target instanceof Node && page.dom.contains(target)
  }
  for (const type of ["wheel", "pointerdown", "keydown"]) addEventListener(type, input, { capture: true, passive: true })
  const leads = () => !pageLeads && !parent.hasAttribute("data-folded") && align(source, page)
  const follows = () => pageLeads && align(page, source)
  source.scrollDOM.addEventListener("scroll", leads)
  page.scrollDOM.addEventListener("scroll", follows)
  // After the page's first layout.
  page.requestMeasure({ read: () => undefined, write: () => align(source, page) })
  return {
    follow(update: ViewUpdate) {
      for (const tr of update.transactions) {
        if (tr.docChanged && !tr.annotation(synced)) page.dispatch({ changes: tr.changes, annotations: synced.of(true) })
      }
    },
    destroy() {
      for (const type of ["wheel", "pointerdown", "keydown"]) removeEventListener(type, input, { capture: true })
      source.scrollDOM.removeEventListener("scroll", leads)
      page.destroy()
      divider.remove()
      parent.removeAttribute("data-folded")
    },
  }
}
