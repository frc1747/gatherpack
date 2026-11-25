import { Controller } from "@hotwired/stimulus"

const HEX = /^#[0-9a-f]{6}$/i

// The Colors section of the theme page. The server works out every color: this
// only passes the picks to the preview iframes and shows what comes back.
export default class extends Controller {
  static targets = ["color", "frame", "warnings"]
  static values = { url: String }

  pick({ target }) {
    const row = this.row(target)
    this.hexInput(row).value = target.value
    this.automaticBox(row).checked = false
    this.refresh()
  }

  type({ target }) {
    const row = this.row(target)
    const value = target.value.trim()
    if (HEX.test(value)) this.picker(row).value = value
    this.automaticBox(row).checked = value === ""
    this.refresh()
  }

  toggleAutomatic({ target }) {
    const row = this.row(target)
    this.hexInput(row).value = target.checked ? "" : this.picker(row).value
    this.refresh()
  }

  reset() {
    this.colorTargets.forEach((row) => {
      this.hexInput(row).value = ""
      this.automaticBox(row).checked = true
    })
    this.refresh()
  }

  refresh() {
    clearTimeout(this.timer)
    this.timer = setTimeout(() => this.load(), 200)
  }

  disconnect() {
    clearTimeout(this.timer)
  }

  load() {
    this.frameTargets.forEach((frame) => {
      // replace(), so editing colors doesn't fill the Back button.
      frame.contentWindow.location.replace(this.previewUrl(frame.dataset.mode))
    })
  }

  previewUrl(mode) {
    const query = new URLSearchParams({ mode })
    this.colorTargets.forEach((row) => {
      const value = this.hexInput(row).value.trim()
      if (HEX.test(value)) query.set(row.dataset.field, value)
    })
    return `${this.urlValue}?${query}`
  }

  // The light frame's document carries the warnings for the current picks.
  frameLoaded({ target }) {
    if (target.dataset.mode !== "light") return

    const warnings = target.contentDocument?.getElementById("palette-warnings")
    if (warnings) this.warningsTarget.replaceChildren(document.importNode(warnings.content, true))
  }

  row(element) { return element.closest("[data-theme-palette-target=color]") }
  picker(row) { return row.querySelector("[data-picker]") }
  hexInput(row) { return row.querySelector("[data-hex]") }
  automaticBox(row) { return row.querySelector("[data-automatic]") }
}
