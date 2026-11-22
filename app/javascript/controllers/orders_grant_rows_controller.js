import { Controller } from "@hotwired/stimulus"

// Orders grant rows (Orders setup, approval steps): shows only the pickers
// the row's "Who" needs, and adds blank rows from the template. Without
// JavaScript every picker shows and the form adds one row per save.
export default class extends Controller {
  static targets = ["list", "template", "add", "who"]

  connect() {
    if (this.hasAddTarget && this.hasTemplateTarget) this.addTarget.hidden = false
    this.whoTargets.forEach((select) => this.show(select))
  }

  add() {
    const html = this.templateTarget.innerHTML.replaceAll("NEW_ROW", `${Date.now()}`)
    this.listTarget.insertAdjacentHTML("beforeend", html)
  }

  change(event) {
    this.show(event.target)
  }

  whoTargetConnected(select) {
    this.show(select)
  }

  show(select) {
    const row = select.closest("[data-orders-grant-row]")
    if (!row) return

    row.querySelectorAll("[data-for-kind]").forEach((part) => {
      const shown = part.dataset.forKind.split(" ").includes(select.value)
      part.hidden = !shown
      part.querySelectorAll("select").forEach((input) => { input.disabled = !shown })
    })
  }
}
