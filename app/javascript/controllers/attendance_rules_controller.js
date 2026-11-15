import { Controller } from "@hotwired/stimulus"

// The attendance item's rules table: add and remove rows, and the "every
// May–Aug" shortcut, which fills in a row's dates with the first such span
// of months starting on or after the item's start (a span may run into the
// next year). Changes bubble to the item form, so the preview refreshes.
export default class extends Controller {
  static targets = ["rows", "template"]
  static values = { from: String }

  connect() {
    this.refresh()
  }

  add(event) {
    event.preventDefault()
    const html = this.templateTarget.innerHTML.replaceAll("__INDEX__", `${Date.now()}`)
    this.rowsTarget.insertAdjacentHTML("beforeend", html)
    this.refresh()
    this.changed()
  }

  remove(event) {
    event.preventDefault()
    event.target.closest("tr").remove()
    this.refresh()
    this.changed()
  }

  // Shows the date or the "within the last" fields for the start picked.
  showStart(event) {
    this.toggleStart(event.target.closest("tr"))
  }

  toggleStart(row) {
    const mode = row.querySelector("[data-field=starts-mode]").value
    row.querySelectorAll("[data-start]").forEach((field) => field.classList.toggle("d-none", field.dataset.start !== mode))
  }

  fill(event) {
    event.preventDefault()
    const row = event.target.closest("tr")
    const first = parseInt(row.querySelector("[data-month=from]").value, 10)
    const last = parseInt(row.querySelector("[data-month=to]").value, 10)
    const [fromYear, fromMonth] = this.fromValue.split("-").map((part) => parseInt(part, 10))
    const year = fromMonth > first ? fromYear + 1 : fromYear
    const endYear = last < first ? year + 1 : year
    const lastDay = new Date(endYear, last, 0).getDate()

    row.querySelector("[data-field=starts-mode]").value = "date"
    row.querySelector("[data-field=starts-date]").value = `${year}-${pad(first)}-01`
    row.querySelector("[data-field=ends-on]").value = `${endYear}-${pad(last)}-${pad(lastDay)}`
    this.toggleStart(row)
    this.changed()
  }

  // Gives every row a key (a rule's link to another is by key, so renaming
  // it breaks nothing) and keeps each "counted together with" choice listing
  // the other rules by their current names.
  refresh() {
    const rows = Array.from(this.rowsTarget.querySelectorAll("tr"))
    rows.forEach((row) => {
      const key = row.querySelector("[data-field=key]")
      if (!key.value) key.value = Math.random().toString(36).slice(2, 10).padEnd(8, "0")
    })
    rows.forEach((row, index) => {
      const select = row.querySelector("[data-field=with]")
      const own = row.querySelector("[data-field=key]").value
      const chosen = select.value
      const blank = select.options[0]
      select.replaceChildren(blank)
      rows.forEach((other, otherIndex) => {
        const key = other.querySelector("[data-field=key]").value
        if (key === own) return
        const name = other.querySelector("[data-field=name]").value.trim()
        if (!name && !other.querySelector("input[name$='[share]']").value) return
        select.add(new Option(name || `Rule ${otherIndex + 1}`, key, false, key === chosen))
      })
      select.value = chosen
    })
  }

  changed() {
    this.element.dispatchEvent(new Event("change", { bubbles: true }))
  }
}

function pad(number) {
  return `${number}`.padStart(2, "0")
}
