import { Controller } from "@hotwired/stimulus"

// Sorting and filtering the checklist report in the page. The rows hold
// only what the viewer may see, so sorting and filtering can't reveal more.
export default class extends Controller {
  static targets = ["table", "name", "overall", "notDone"]

  sort(event) {
    const header = event.currentTarget
    const table = header.closest("table")
    const index = Array.from(header.parentElement.children).indexOf(header)
    const ascending = header.dataset.direction !== "asc"
    header.parentElement.querySelectorAll("th").forEach((th) => delete th.dataset.direction)
    header.dataset.direction = ascending ? "asc" : "desc"

    const body = table.tBodies[0]
    const rows = Array.from(body.rows)
    rows.sort((a, b) => {
      const x = a.cells[index].dataset.value || ""
      const y = b.cells[index].dataset.value || ""
      const result = isNaN(x) || isNaN(y) ? x.localeCompare(y) : Number(x) - Number(y)
      return ascending ? result : -result
    })
    rows.forEach((row) => body.appendChild(row))
  }

  filter() {
    const name = this.nameTarget.value.trim().toLowerCase()
    const ticked = this.overallTargets.filter((box) => box.checked).map((box) => box.value)
    const notDone = this.notDoneTarget.checked

    this.tableTargets.forEach((table) => {
      Array.from(table.tBodies[0].rows).forEach((row) => {
        const status = row.dataset.overall
        const shown = (!name || row.dataset.name.includes(name)) &&
          (ticked.length === 0 || ticked.includes(status)) &&
          (!notDone || status !== "met")
        row.classList.toggle("d-none", !shown)
      })
    })
  }
}
