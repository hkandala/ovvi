import type { Ovvi } from "@ovvi/plugin-api"
import { how, menu, open as opening, symbols } from "./place"

type Head = { branch: string; ahead: number; behind: number } | null

const plural = (count: number, word: string) => `${count} ${word}${count === 1 ? "" : "s"}`

export function footer(ovvi: Ovvi, bar: HTMLElement, again: () => void) {
  const machine = ovvi.card.machine
  bar.innerHTML = `<span class="machine" hidden></span><span class="folder"></span><span class="git" hidden><span
    class="branch"></span><span class="added"></span><span class="removed"></span><button class="pull"></button><button
    class="push"></button><button class="fetch" title="Fetch" aria-label="Fetch"></button><span class="rule"></span><button
    class="open" title="Open in Git" aria-label="Open in Git">Git</button></span>`
  const [where, folder, git, branch, added, removed] = bar.querySelectorAll("span")
  const [pull, push, fetch, open] = bar.querySelectorAll("button")
  symbols(ovvi, ["server.rack", "folder", "source.branch", "arrow.down", "arrow.up", "arrow.triangle.2.circlepath",
    "arrow.up.right.square"], 11)
  where.hidden = !machine.remote
  where.textContent = machine.name
  let repo: string | null = null
  open.onclick = (event) => {
    if (repo) opening(ovvi, `${repo}/`, how(event), "git")
  }
  open.oncontextmenu = (event) => {
    if (repo) void menu(ovvi, event, `${repo}/`, { plugin: "git" })
  }
  /** git prints its `hint:` lines ahead of the error. */
  const write = (button: HTMLButtonElement, done: (root: string) => Promise<void>) => async () => {
    if (!repo) return
    button.toggleAttribute("data-busy", true)
    for (const each of [pull, push, fetch]) each.disabled = true
    await done(repo).catch((error) => {
      const lines = String((error as Error).message ?? error).split("\n").filter((l) => l.trim() && !l.startsWith("hint:"))
      void ovvi.toast(lines.slice(-2).join(" "))
    })
    button.toggleAttribute("data-busy", false)
    for (const each of [pull, push, fetch]) each.disabled = false
    again()
  }
  pull.onclick = write(pull, (root) => ovvi.git.pull(root))
  push.onclick = write(push, (root) => ovvi.git.push(root))
  fetch.onclick = write(fetch, (root) => ovvi.git.fetch(root))
  return {
    folder(folders: number, files: number, hidden: number) {
      folder.textContent = `${plural(folders, "folder")}, ${plural(files, "file")}${hidden ? ` · ${hidden} hidden` : ""}`
    },
    repo(root: string | null, head: Head, lines: { added: number; removed: number }) {
      repo = root
      git.hidden = !root || !head
      if (!head) return
      branch.textContent = head.branch
      added.textContent = lines.added ? `+${lines.added}` : ""
      removed.textContent = lines.removed ? `−${lines.removed}` : ""
      for (const [button, count, word] of [[pull, head.behind, "Pull"], [push, head.ahead, "Push"]] as const) {
        button.hidden = !count
        button.textContent = String(count)
        button.title = `${word}, ${count} ${word === "Pull" ? "behind" : "ahead"}`
        button.ariaLabel = button.title
      }
    },
  }
}
