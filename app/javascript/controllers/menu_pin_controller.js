import { Controller } from "@hotwired/stimulus"
import { Turbo } from "@hotwired/turbo-rails"

const EDITING_KEY = "mg-menu-editing"

// The sidebar's pin buttons. A pin is saved for the person, then the page is
// drawn again so the Pinned group and every copy of the item agree. Edit menu
// shows the pins on screens with no hover, and stays on while pinning.
export default class extends Controller {
  static targets = [ "edit" ]
  static values = { url: String }

  connect() {
    this.setEditing(this.storedEditing())
  }

  async toggle({ params: { key, pinned } }) {
    const url = pinned ? `${this.urlValue}/${encodeURIComponent(key)}` : this.urlValue
    const response = await fetch(url, {
      method: pinned ? "DELETE" : "POST",
      headers: {
        "Accept": "application/json",
        "Content-Type": "application/json",
        "X-CSRF-Token": document.querySelector("meta[name=csrf-token]")?.content
      },
      body: pinned ? null : JSON.stringify({ path_key: key })
    })
    if (response.ok) Turbo.visit(window.location.href, { action: "replace" })
  }

  edit() {
    const editing = !this.element.classList.contains("mg-menu-editing")
    this.setEditing(editing)
    try {
      if (editing) sessionStorage.setItem(EDITING_KEY, "on")
      else sessionStorage.removeItem(EDITING_KEY)
    } catch {
      // Without storage, editing just ends with the page.
    }
  }

  setEditing(editing) {
    this.element.classList.toggle("mg-menu-editing", editing)
    this.editTargets.forEach((button) => button.setAttribute("aria-pressed", String(editing)))
  }

  storedEditing() {
    try {
      return sessionStorage.getItem(EDITING_KEY) === "on"
    } catch {
      return false
    }
  }
}
