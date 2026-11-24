import { Controller } from "@hotwired/stimulus"

// A Manage part that folds open or shut from its heading. Which parts are
// folded is display state, so it's kept in this browser, per person and part.
export default class extends Controller {
  static targets = [ "toggle", "items" ]
  static values = { key: String }

  connect() {
    this.apply(this.stored())
  }

  toggle() {
    const folded = !this.itemsTarget.hidden
    this.store(folded)
    this.apply(folded)
  }

  apply(folded) {
    this.itemsTarget.hidden = folded
    this.toggleTarget.setAttribute("aria-expanded", String(!folded))
  }

  stored() {
    try {
      return localStorage.getItem(this.keyValue) === "folded"
    } catch {
      return false
    }
  }

  store(folded) {
    try {
      if (folded) localStorage.setItem(this.keyValue, "folded")
      else localStorage.removeItem(this.keyValue)
    } catch {
      // Without storage the part still folds, just not across pages.
    }
  }
}
