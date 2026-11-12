import type { Ovvi, Page } from "@ovvi/plugin-api"
import places from "../places.json"

export type Place = Page & {
  read?: ReturnType<Ovvi["files"]["read"]>
  trail: string[]
}

type Own = {
  hiddenFiles?: boolean; mode?: string; locked?: boolean; preview?: boolean; wrap?: boolean; side?: boolean
  sideWidth?: number
}
export const own = (ovvi: Ovvi) => ovvi.state.get<Own>() ?? {}
export const choose = (ovvi: Ovvi, change: Own) => ovvi.state.set({ ...ovvi.state.get<object>(), ...change })

/** "" for a dotfile's name, as `NSString.pathExtension`. */
export const extension = (path: string) => (/[^/]\.([^./]+)$/.exec(path)?.[1] ?? "").toLowerCase()

export const fileURL = (path: string) => `file://${path.split("/").map(encodeURIComponent).join("/")}`

/** This Mac only: a remote card never shows a file over `file:`. */
export const htmlPage = (ovvi: Ovvi, path: string) =>
  !ovvi.card.machine.remote && path.startsWith("/") && ["html", "htm"].includes(extension(path))
    ? fileURL(path) : undefined

export const drawn = (path: string) => {
  const ext = extension(path)
  return (["image", "pdf", "audio", "video"] as const).find((group) => places[group].includes(ext)) ?? ""
}

/** As the app's `ExplorerPlace` reads places.json. */
export function kind(arg: string): "files" | "file" | "preview" | "markdown" {
  if (arg.endsWith("/")) return "files"
  const ext = extension(arg)
  if (places.markdown.includes(ext)) return "markdown"
  return drawn(arg) || places.binary.includes(ext) ? "preview" : "file"
}

export type Reveal = ((at: string) => void) | undefined

type How = "card" | "tab" | "side"
export const how = (event: MouseEvent | KeyboardEvent): How => (event.metaKey ? "tab" : event.altKey ? "side" : "card")

export const open = (ovvi: Ovvi, arg: string, how: How, plugin?: string) =>
  void ovvi.open(arg, { plugin, how, background: how !== "card" }).catch((error) => console.error(error))

export async function menu(ovvi: Ovvi, event: MouseEvent, arg: string,
  more: { rename?: () => void; link?: string; plugin?: string } = {}) {
  event.preventDefault()
  const picked = await ovvi.menu.show([
    // A web address that ends in `/` is no folder.
    { value: "card", title: arg.endsWith("/") && !more.plugin && !/^[a-z][a-z0-9+.-]*:/i.test(arg) ? "Open as Root" : "Open" },
    { value: "tab", title: "Open in New Tab" },
    { value: "side", title: "Open to the Side" },
    ...(more.rename ? ["-" as const, { value: "rename", title: "Rename" }] : []),
    ...(more.link ? ["-" as const, { value: "copy", title: "Copy Link" }] : []),
  ])
  if (picked === "rename") more.rename?.()
  else if (picked === "copy" && more.link) ovvi.clipboard.write(more.link).catch(console.error)
  else if (picked) open(ovvi, arg, picked as How, more.plugin)
}

export const sf = (name: string) => `--sf-${name.replaceAll(".", "-")}`

/** In a sheet of their own: the app sets the root's inline style on each theme change, which drops any property set
 *  there. */
const loaded = new Set<string>()
const sheet = document.head.appendChild(document.createElement("style")).sheet!
export function symbols(ovvi: Ovvi, names: string[], size = 12) {
  for (const name of names.filter((name) => !loaded.has(name))) {
    loaded.add(name)
    void ovvi.symbol(name, size).then(
      (url) => sheet.insertRule(`:root { ${sf(name)}: url(${url}) }`),
      () => loaded.delete(name),
    )
  }
}

export const name = (path: string) => (path === "/" ? "/" : path.replace(/\/$/, "").split("/").pop() ?? "")

export async function trail(ovvi: Ovvi, path: string) {
  const root = await ovvi.git.root(path.slice(0, path.lastIndexOf("/")) || "/").catch(() => null)
  // git names the root with its links resolved: `/tmp` is `/private/tmp`.
  const repo = root && [root, root.replace(/^\/private(?=\/)/, "")].find((each) => path.startsWith(`${each}/`))
  // ponytail: the home folder where macOS and Linux put it; ask the machine if one lives elsewhere.
  const home = /^\/(?:Users\/(?!Shared\/)|home\/)[^/]+(?=\/)|^\/root(?=\/)/.exec(path)?.[0]
  const base = (repo !== home && repo) || home || ""
  return [base === home ? "~" : base ? name(base) : "/", ...path.slice(base.length).split("/").filter(Boolean)]
}
