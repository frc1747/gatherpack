import { Controller } from "@hotwired/stimulus"

// The form page's totals and printing. "Hide totals" folds the totals away
// and remembers that in this browser (a convenience: without storage, or
// without JavaScript, the link's ?totals=hidden does the same for one visit).
// Hidden totals don't print. The Table/Labels choice decides what Print
// prints: the table on screen, or one label per person.
const STORAGE_KEY = "gatherpack.forms.hideTotals"

export default class extends Controller {
  static targets = [ "totals", "toggle", "table", "labels" ]
  static values = { hidden: Boolean }

  connect() {
    if (!this.hiddenValue && this.stored() === "1") this.hiddenValue = true
  }

  toggleTotals(event) {
    event.preventDefault()
    this.hiddenValue = !this.hiddenValue
    this.store(this.hiddenValue ? "1" : "0")
  }

  hiddenValueChanged() {
    if (!this.hasTotalsTarget) return
    this.totalsTarget.hidden = this.hiddenValue
    if (this.hasToggleTarget) this.toggleTarget.textContent = this.hiddenValue ? "Show totals" : "Hide totals"
  }

  chooseLayout(event) {
    const labels = event.target.value === "labels"
    if (this.hasTableTarget) this.tableTarget.classList.toggle("d-print-none", labels)
    if (this.hasLabelsTarget) this.labelsTarget.classList.toggle("d-print-flex", labels)
  }

  print() {
    window.print()
  }

  stored() {
    try {
      return window.localStorage.getItem(STORAGE_KEY)
    } catch {
      return null
    }
  }

  store(value) {
    try {
      window.localStorage.setItem(STORAGE_KEY, value)
    } catch {
      // Storage blocked: the choice lasts until the page is left.
    }
  }
}
