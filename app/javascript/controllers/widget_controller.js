import { Controller } from "@hotwired/stimulus"

// A widget's body. In "replace" mode it moves the content into a shadow root
// with only the widget's own CSS, so app and theme rules don't reach it
// (theme CSS variables still do). Then it runs the widget's JavaScript as
// function (root, widget) { ... }. If that returns a function, it is called
// when the widget goes away (leaving the page, or the widget reloading).
export default class extends Controller {
  static targets = [ "content" ]
  static values = { id: String, title: String, mode: String, stylesheet: String, code: String }

  connect() {
    const root = this.modeValue === "replace" ? this.shadowRoot() : this.element
    if (this.codeValue.trim() === "") return

    const widget = {
      id: this.idValue,
      title: this.titleValue,
      refresh: () => this.element.closest("turbo-frame")?.reload()
    }

    try {
      const cleanup = new Function("root", "widget", this.codeValue)(root, widget)
      if (typeof cleanup === "function") this.cleanup = cleanup
    } catch (error) {
      console.error(`Widget "${this.titleValue}" (${this.idValue}) failed:`, error)
    }
  }

  disconnect() {
    if (!this.cleanup) return

    try {
      this.cleanup()
    } catch (error) {
      console.error(`Widget "${this.titleValue}" (${this.idValue}) failed to clean up:`, error)
    }
    this.cleanup = null
  }

  shadowRoot() {
    if (this.element.shadowRoot) return this.element.shadowRoot

    const shadow = this.element.attachShadow({ mode: "open" })
    const style = document.createElement("style")
    style.textContent = this.stylesheetValue
    shadow.append(style)
    if (this.hasContentTarget) shadow.append(this.contentTarget.content.cloneNode(true))
    return shadow
  }
}
