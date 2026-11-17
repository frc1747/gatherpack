import { Controller } from "@hotwired/stimulus"

// Keeps the time kiosk's Token box ready for a card scanner on a touch screen.
// A scanner types into whatever has focus, so a stray tap on the page would
// otherwise swallow the next scan. Taps on buttons, links and fields still
// work; anything else sends the cursor back to the Token box. While a window
// (the Manager window) is open it leaves focus alone.
export default class extends Controller {
  static INTERACTIVE = "a, button, input, select, textarea, label, summary, [contenteditable], [role=button], [tabindex]:not([tabindex='-1'])"

  connect() {
    this.refocus = this.refocus.bind(this)
    this.onFocusOut = this.onFocusOut.bind(this)
    this.onPointerDown = this.onPointerDown.bind(this)

    document.addEventListener("pointerdown", this.onPointerDown, true)
    document.addEventListener("focusout", this.onFocusOut)
    document.addEventListener("hidden.bs.modal", this.refocus)
    window.addEventListener("focus", this.refocus)

    this.refocus()
  }

  disconnect() {
    document.removeEventListener("pointerdown", this.onPointerDown, true)
    document.removeEventListener("focusout", this.onFocusOut)
    document.removeEventListener("hidden.bs.modal", this.refocus)
    window.removeEventListener("focus", this.refocus)
  }

  // A tap on plain page area: keep focus where it is instead of dropping it.
  onPointerDown(event) {
    if (this.modalOpen() || event.target.closest(this.constructor.INTERACTIVE)) return

    event.preventDefault()
    this.refocus()
  }

  // Focus left for nowhere (the page itself): bring it back. Wait a moment so
  // a tapped button can finish its click first.
  onFocusOut(event) {
    if (event.target !== this.input || event.relatedTarget) return

    setTimeout(() => {
      if (!document.activeElement || document.activeElement === document.body) this.refocus()
    }, 50)
  }

  refocus() {
    const input = this.input
    if (!input || this.modalOpen() || document.activeElement === input) return

    input.focus({ preventScroll: true })
  }

  modalOpen() {
    return document.querySelector(".modal.show") !== null
  }

  get input() {
    return this.element.querySelector("input[name='time_kiosk[token_value]']")
  }
}
