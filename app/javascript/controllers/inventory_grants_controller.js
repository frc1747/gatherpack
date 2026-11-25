import { Controller } from "@hotwired/stimulus"

// Inventory Managers rows on Inventory setup: shows the pickers the row's
// Who needs (data-who lists the kinds a picker is for) and adds rows from
// the template. Without JavaScript every picker shows and there is one
// blank row to fill in.
export default class extends Controller {
  static targets = ["list", "template", "add", "row"]

  connect() {
    this.addTarget.hidden = false
    this.rowTargets.forEach((row) => this.show(row))
  }

  rowTargetConnected(row) {
    this.show(row)
  }

  reveal(event) {
    this.show(event.target.closest("[data-inventory-grants-target~='row']"))
  }

  add() {
    const html = this.templateTarget.innerHTML.replace(/NEW_ROW|new_row/g, `${Date.now()}`)
    this.listTarget.insertAdjacentHTML("beforeend", html)
    this.listTarget.lastElementChild?.querySelector("select")?.focus()
  }

  show(row) {
    const who = row?.querySelector("select[name$='[who]']")
    if (!who) return

    row.querySelectorAll("[data-who]").forEach((element) => {
      element.hidden = !element.dataset.who.split(" ").includes(who.value)
    })
  }
}
