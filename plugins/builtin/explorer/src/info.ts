import type { Ovvi } from "@ovvi/plugin-api"

/** A size in the Finder's numbers (`ByteCountFormatter`'s file style): 999 bytes, 3 kB, 1.3 MB, 1.23 GB, half up,
 *  in the user's locale. A value that rounds to 1,000 takes the next unit. */
function size(bytes: number) {
  if (bytes === 0) return "Zero kB"
  if (bytes < 1000) return bytes === 1 ? "1 byte" : `${bytes} bytes`
  const digits = [0, 1, 2, 2]
  let value = bytes / 1000, unit = 0
  while (unit < 3 && value >= 1000 - 0.5 / 10 ** digits[unit]) {
    value /= 1000
    unit++
  }
  return new Intl.NumberFormat(undefined, {
    style: "unit",
    unit: ["kilobyte", "megabyte", "gigabyte", "terabyte"][unit],
    unitDisplay: "short",
    maximumFractionDigits: digits[unit],
  }).format(value)
}

export async function info(ovvi: Ovvi, path: string, parent: HTMLElement) {
  const file = await ovvi.files.info(path).catch((error) => failed(error, parent))
  if (!file) return
  const view = document.createElement("div")
  view.className = "info"
  const icon = Object.assign(document.createElement("img"), { src: file.icon, alt: "" })
  const name = Object.assign(document.createElement("div"), { className: "name", textContent: file.name })
  const facts = Object.assign(document.createElement("div"), { textContent: `${file.kind} · ${size(file.size)}` })
  view.append(icon, name, facts)
  parent.replaceChildren(view)
}

export const failed = (error: unknown, parent: HTMLElement) => {
  const text = error instanceof Error ? error.message : String(error)
  parent.replaceChildren(Object.assign(document.createElement("div"), { className: "info", textContent: text }))
}
