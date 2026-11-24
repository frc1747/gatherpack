import { Controller } from "@hotwired/stimulus"

// The form page's totals and printing. "Hide totals" folds the totals away
// and remembers that in this browser (a convenience: without storage, or
// without JavaScript, the link's ?totals=hidden does the same for one visit).
// Hidden totals don't print. The Table/Labels choice decides what Print
// prints: the table on screen, or one label per person.
// The labels and totals follow the table's heading filters and sort
// (table-filter): a label shows for each row left on screen, in its order,
// and each total counts only those people (the server lists who each one
// covers in data-people). With no filter on, both are as the server drew them.
const STORAGE_KEY = "gatherpack.forms.hideTotals"

export default class extends Controller {
  static targets = [ "totals", "toggle", "table", "labels", "label", "count" ]
  static values = { hidden: Boolean }

  connect() {
    if (!this.hiddenValue && this.stored() === "1") this.hiddenValue = true
    if (!this.hasTableTarget) return
    // table-filter hides rows with the hidden attribute and sorts by moving them.
    this.observer = new MutationObserver(() => this.scheduleFollow())
    this.observer.observe(this.tableTarget, { subtree: true, childList: true, attributes: true, attributeFilter: [ "hidden" ] })
  }

  disconnect() {
    this.observer?.disconnect()
  }

  scheduleFollow() {
    if (this.following) return
    this.following = true
    queueMicrotask(() => {
      this.following = false
      this.followTable()
    })
  }

  followTable() {
    const rows = [ ...this.tableTarget.querySelectorAll("tbody tr[id]") ]
    const shown = new Set(rows.filter((row) => !row.hidden).map((row) => row.id))
    if (this.hasLabelsTarget) {
      const labels = new Map(this.labelTargets.map((label) => [ label.dataset.person, label ]))
      for (const row of rows) {
        const label = labels.get(row.id)
        if (!label) continue
        label.hidden = !shown.has(row.id)
        this.labelsTarget.append(label)
      }
    }
    for (const count of this.countTargets) {
      const people = count.dataset.people.split(" ").filter((id) => id !== "")
      count.textContent = people.filter((id) => shown.has(id)).length
    }
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
