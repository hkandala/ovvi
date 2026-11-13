import type { Ovvi } from "@ovvi/plugin-api"
import { createFileTreeIconResolver, getBuiltInSpriteSheet } from "@pierre/trees"
import { ensureFileTreeStyles } from "@pierre/trees/web-components"

export let ovvi: Ovvi
export const bind = (api: Ovvi) => {
  ovvi = api
}

/** A diff is `<home> <source>`, as the app's `PaneLabel.diffSource`. */
export function parse(arg: string) {
  const space = arg.lastIndexOf(" "), diff = space > 0 && arg.slice(0, space).endsWith("/")
  const folder = diff ? arg.slice(0, space) : arg
  return { root: folder.length > 1 && folder.endsWith("/") ? folder.slice(0, -1) : folder,
    source: diff ? arg.slice(space + 1) : undefined }
}

export const home = (root: string) => (root.endsWith("/") ? root : `${root}/`)

export type How = "card" | "tab" | "side" | "mac"
/** ⌘⌥: the Mac's default app, as a terminal's links. A commit, which no app opens, takes `files: false`: ⌘ wins. */
export const how = (event: MouseEvent | KeyboardEvent, files = true): How =>
  files && event.metaKey && event.altKey ? "mac" : event.metaKey ? "tab" : event.altKey ? "side" : "card"

export const open = (arg: string, options: { how: How; at?: string; plugin?: string }) =>
  void ovvi.open(arg, { ...options, background: options.how !== "card" }).catch((error) => console.error(error))

export async function menu(event: MouseEvent, arg: string, options: { at?: string; plugin?: string }) {
  event.preventDefault()
  const picked = await ovvi.menu.show([
    { value: "card", title: "Open" }, { value: "tab", title: "Open in New Tab" }, { value: "side", title: "Open to the Side" },
  ])
  if (picked) open(arg, { ...options, how: picked as How })
}

export function element<K extends keyof HTMLElementTagNameMap>(tag: K, className = "", text = "") {
  const node = document.createElement(tag)
  node.className = className
  node.textContent = text
  return node
}

export function nameAndFolder(path: string): [string, string] {
  const slash = path.lastIndexOf("/")
  return [path.slice(slash + 1), path.slice(0, Math.max(slash, 0))]
}

export const sf = (name: string) => `--sf-${name.replaceAll(".", "-")}`

export function symbol(name: string, className = "symbol") {
  const node = element("span", className)
  node.style.setProperty("--symbol", `var(${sf(name)})`)
  node.ariaHidden = "true"
  return node
}

const icons = createFileTreeIconResolver("complete")
let sprite: Document | undefined

export function fileIcon(path: string) {
  sprite ??= new DOMParser().parseFromString(getBuiltInSpriteSheet("complete"), "text/html")
  const { name, token } = icons.resolveIcon("file-tree-icon-file", path), shape = sprite.getElementById(name)
  const node = element("span", "file-icon"), root = node.attachShadow({ mode: "open" })
  node.ariaHidden = "true"
  ensureFileTreeStyles(root)
  root.innerHTML = `<div data-file-tree-colored-icons="true"><svg data-icon-token="${token ?? ""}" width="16" height="16"
    style="display: block" viewBox="${shape?.getAttribute("viewBox") ?? "0 0 16 16"}">${shape?.innerHTML ?? ""}</svg></div>`
  return node
}

type Kept = { draft?: string; list?: boolean; layout?: string; wrap?: boolean }
export const kept = () => ovvi.state.get<Kept>() ?? {}
export const keep = (change: Kept) => ovvi.state.set({ ...ovvi.state.get<object>(), ...change })

export function coalesce(work: () => Promise<void>) {
  let running: Promise<void> | undefined
  let again = false
  return (): Promise<void> => {
    if (running) {
      again = true
      return running
    }
    running = (async () => {
      try {
        do {
          again = false
          await work()
        } while (again)
      } finally {
        running = undefined
      }
    })()
    return running
  }
}

/** The short hash as a button: a click copies the whole one and says Copied for a moment. */
export function copyButton(hash: string, length: number) {
  const short = hash.slice(0, length), node = element("button", "hash", short)
  node.title = "Copy"
  node.ariaLabel = `Copy ${hash}`
  node.onclick = (event) => {
    event.stopPropagation()
    ovvi.clipboard.write(hash).then(() => {
      node.textContent = "Copied"
      setTimeout(() => (node.textContent = short), 1200)
    }, failed)
  }
  return node
}

export async function failed(error: Error) {
  const text = error.message.split("\n").map((line) => line.trim()).join(" ")
  if ((await ovvi.toast(text, ["Copy", "OK"])) === "Copy") ovvi.clipboard.write(error.message).catch(console.error)
}
