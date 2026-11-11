declare module "@novnc/novnc" {
  export default class RFB extends EventTarget {
    constructor(target: HTMLElement, url: string, options?: { credentials?: { username?: string; password?: string } })
    scaleViewport: boolean
    background: string
    viewOnly: boolean
    focus(): void
    disconnect(): void
    sendCredentials(credentials: { username: string; password: string }): void
  }
}
