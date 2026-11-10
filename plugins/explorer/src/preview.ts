import type { OvviError } from "@ovvi/plugin-api"
import { failed, info } from "./info"
import { drawn, extension, type Place, type Reveal } from "./place"

const ZOOM = ["fit", "actual", "out", "in"] as const
type Zoom = (typeof ZOOM)[number]
let styled: Promise<unknown> | undefined

export async function show(place: Place): Promise<Reveal> {
  const { ovvi, arg: path, element: root, keep } = place
  const ext = extension(path), group = drawn(path)
  let zoom: (to: Zoom) => void = () => {}
  let release = () => {}
  keep(() => release())
  for (const step of ZOOM) ovvi.controls.set(`zoom.${step}`, { hidden: group !== "image" && group !== "pdf" })
  ovvi.on("control", ({ id }) => {
    const step = ZOOM.find((step) => id === `zoom.${step}`)
    if (step) zoom(step)
  })
  const page = (text: string) => ovvi.controls.set("page", { value: text, hidden: !text })

  const image = (url: string, fallback: () => void) => {
    const box = Object.assign(document.createElement("div"), { className: "scroller" })
    const img = Object.assign(new Image(), { src: url, alt: path.split("/").pop() ?? "" })
    box.append(img)
    root.replaceChildren(box)
    let scale: number | "fit" = "fit"
    const fit = () => Math.min(1, box.clientWidth / img.naturalWidth, box.clientHeight / img.naturalHeight)
    const apply = () => {
      img.style.width = `${img.naturalWidth * (scale === "fit" ? fit() : scale)}px`
    }
    img.onload = apply
    img.onerror = fallback
    const observer = new ResizeObserver(apply)
    observer.observe(box)
    release = () => observer.disconnect()
    zoom = (to) => {
      const now = scale === "fit" ? fit() : scale
      scale = to === "fit" ? "fit" : to === "actual" ? 1 : Math.min(16, Math.max(0.05, now * (to === "in" ? 1.25 : 0.8)))
      apply()
    }
  }

  const pdf = async (data: Uint8Array, fallback: () => void) => {
    const pdfjs = await import("pdfjs-dist")
    pdfjs.GlobalWorkerOptions.workerSrc = "pdf.worker.min.mjs"
    // The viewer reads the library from here.
    Object.assign(globalThis, { pdfjsLib: pdfjs })
    const { EventBus, PDFViewer } = await import("pdfjs-dist/web/pdf_viewer.mjs")
    // pdf.js's viewer styles are 124 KB: only in a card that shows a PDF.
    styled ??= new Promise((done) => {
      const link = Object.assign(document.createElement("link"), { rel: "stylesheet", href: "pdf_viewer.css" })
      document.head.append(Object.assign(link, { onload: done, onerror: done }))
    })
    await styled
    if (place.dropped) return
    const container = Object.assign(document.createElement("div"), { className: "pdf" })
    container.append(Object.assign(document.createElement("div"), { className: "pdfViewer" }))
    root.replaceChildren(container)
    const eventBus = new EventBus()
    const viewer = new PDFViewer({ container, eventBus })
    const scales: Record<Zoom, string> = { fit: "page-width", actual: "page-actual", in: "", out: "" }
    eventBus.on("pagesinit", () => {
      viewer.currentScaleValue = scales.fit
    })
    eventBus.on("pagechanging", ({ pageNumber }: { pageNumber: number }) => page(`${pageNumber} of ${viewer.pagesCount}`))
    // The scheme serves pdf.js's fonts, maps and decoders from the plugin's one folder.
    const task = pdfjs.getDocument({ data, wasmUrl: "./", standardFontDataUrl: "./", cMapUrl: "./" })
    // Ends the document and its worker, also of a load under way.
    release = () => void task.destroy()
    const document_ = await task.promise.catch(() => undefined)
    if (!document_ || place.dropped) {
      release()
      return !place.dropped && fallback()
    }
    viewer.setDocument(document_)
    page(`1 of ${document_.numPages}`)
    zoom = (to) => {
      if (to === "in") viewer.increaseScale()
      else if (to === "out") viewer.decreaseScale()
      else viewer.currentScaleValue = scales[to]
    }
  }

  let hash: string | undefined
  const draw = async () => {
    if (!group) return info(ovvi, path, root)
    if (hash && (await ovvi.files.info(path).catch(() => undefined))?.hash === hash) return
    const file = await ovvi.files.readBytes(path).catch((error: OvviError) => error)
    if (place.dropped || (!(file instanceof Error) && file.hash === hash)) return
    zoom = () => {}
    release()
    release = () => {}
    page("")
    if (file instanceof Error) {
      hash = undefined
      return file.code === "tooLarge" ? info(ovvi, path, root) : failed(file, root)
    }
    hash = file.hash
    const fallback = () => {
      zoom = () => {}
      page("")
      void info(ovvi, path, root)
    }
    if (group === "pdf") return pdf(file.data, fallback)
    const type = file.type === "application/octet-stream" ? `${group}/${ext}` : file.type
    const url = URL.createObjectURL(new Blob([file.data as BlobPart], { type }))
    const revoke = () => URL.revokeObjectURL(url)
    if (group === "image") {
      image(url, fallback)
      const observed = release
      release = () => {
        observed()
        revoke()
      }
      return
    }
    const player = document.createElement(group === "audio" ? "audio" : "video")
    Object.assign(player, { src: url, controls: true, className: "player", onerror: fallback })
    root.replaceChildren(player)
    release = revoke
  }

  /** One draw at a time, in order: a PDF loads over several turns. */
  let shown = draw()
  ovvi.files.watch(path, () => {
    shown = shown.then(draw, draw)
  })
  await shown
  return undefined
}
