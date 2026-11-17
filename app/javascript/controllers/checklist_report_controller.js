import { Controller } from "@hotwired/stimulus"

// Sorting and filtering the checklist report in the page. The rows hold
// only what the viewer may see, so sorting and filtering can't reveal more.
// Ticks under one heading mean "any of these"; headings, number bounds and
// the name filter combine.
export default class extends Controller {
  static targets = ["table", "name", "notDone", "tick", "bound"]

  sort(event) {
    const header = event.currentTarget.closest("th")
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

  filter(event) {
    // A tick in one table's heading applies to every section.
    if (event?.target?.dataset?.column && event.target.type === "checkbox") {
      this.tickTargets
        .filter((box) => box.dataset.column === event.target.dataset.column && box.value === event.target.value)
        .forEach((box) => { box.checked = event.target.checked })
    }

    const name = this.nameTarget.value.trim().toLowerCase()
    const notDone = this.hasNotDoneTarget && this.notDoneTarget.checked
    const ticks = {}
    this.tickTargets.filter((box) => box.checked).forEach((box) => {
      (ticks[box.dataset.column] ||= new Set()).add(box.value)
    })
    const bounds = this.boundTargets.filter((input) => input.value !== "")

    this.tableTargets.forEach((table) => {
      Array.from(table.tBodies[0].rows).forEach((row) => {
        const shown = (!name || row.dataset.name.includes(name)) &&
          (!notDone || row.cells[1].dataset.status !== "met") &&
          Object.entries(ticks).every(([column, values]) => values.has(row.cells[column].dataset.status)) &&
          bounds.every((input) => this.withinBound(row.cells[input.dataset.column], input))
        row.classList.toggle("d-none", !shown)
      })
    })
  }

  withinBound(cell, input) {
    let measures = {}
    try { measures = JSON.parse(cell.dataset.measures || "{}") } catch { measures = {} }
    const value = Number(measures[input.dataset.key])
    if (Number.isNaN(value) || measures[input.dataset.key] === undefined) return false
    return input.dataset.bound === "min" ? value >= Number(input.value) : value <= Number(input.value)
  }
}
