import { Controller } from "@hotwired/stimulus"

// A filter bar that shows its choice as soon as it's made. A change under
// "More choices" submits the form, except inside an element marked
// data-filter-bar-wait (a choice made in steps), which waits for Show. With
// auto (the bar's auto_submit:) a change to a field or the team select does
// too, and the top-row Show is hidden once this runs, so without JavaScript
// it stays and still works. It also stays while More choices is there. Text
// boxes fire change on leaving them (or Enter submits), not on each key.
// Applying a choice keeps the page where it was scrolled to, so the table
// and the choices don't jump away from the person choosing.
const SCROLL_KEY = "filter-bar-scroll"

export default class extends Controller {
  static targets = [ "show" ]
  static values = { auto: Boolean }

  connect() {
    if (this.autoValue && !this.element.querySelector("details")) this.showTargets.forEach((button) => { button.hidden = true })
    this.remember = () => this.store({ path: new URL(this.element.action, window.location.href).pathname, y: window.scrollY })
    this.element.addEventListener("submit", this.remember)
    this.restore()
  }

  disconnect() {
    this.element.removeEventListener("submit", this.remember)
  }

  submit(event) {
    if (event.target.closest("[data-filter-bar-wait]")) return
    if (!this.autoValue && !event.target.closest("details")) return
    this.element.requestSubmit()
  }

  // private

  store(value) {
    try { window.sessionStorage.setItem(SCROLL_KEY, JSON.stringify(value)) } catch { /* storage off: the page opens at the top */ }
  }

  restore() {
    let saved = null
    try {
      saved = JSON.parse(window.sessionStorage.getItem(SCROLL_KEY) || "null")
      window.sessionStorage.removeItem(SCROLL_KEY)
    } catch { return }
    if (!saved || saved.path !== window.location.pathname) return
    requestAnimationFrame(() => window.scrollTo(0, saved.y))
  }
}
