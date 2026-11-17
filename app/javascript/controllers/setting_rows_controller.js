import { Controller } from "@hotwired/stimulus"

// Adds a row to a settings picker (badge grants, lists) from its template.
// Without JavaScript the picker still has one blank row to fill in.
export default class extends Controller {
  static targets = ["list", "template", "add"]

  connect() {
    this.addTarget.hidden = false
  }

  add() {
    const index = `${Date.now()}`
    const html = this.templateTarget.innerHTML.replace(/NEW_ROW|new_row/g, index)
    this.listTarget.insertAdjacentHTML("beforeend", html)
    const field = this.listTarget.lastElementChild?.querySelector("select, input:not([type=hidden])") ||
      (this.listTarget.lastElementChild?.matches?.("input") ? this.listTarget.lastElementChild : null)
    field?.focus()
  }
}
