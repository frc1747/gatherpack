import { Controller } from "@hotwired/stimulus"

// A Columns dropdown for the tables inside this element (listed from the
// first one's headings): one tick box per
// heading, and unticking one hides that column's heading and cells. The
// choice is remembered per viewer under key (by heading text, so a column
// added later shows) and applied on load, so Print shows the same columns.
// Headings marked data-column-chooser-fixed, or with no text, always show
// and aren't listed. At least one listed column stays ticked. The dropdown
// goes in the slot target (a filter bar's table actions) when there is one,
// else just above the table.
// A heading's name in the list: the text of an element inside it marked
// data-column-chooser-label (for headings that also hold controls, such as a
// filter menu), else all its text.
function headingText(cell) {
  return (cell.querySelector("[data-column-chooser-label]") || cell).textContent.trim()
}

export default class extends Controller {
  static targets = [ "slot" ]
  static values = { key: String }

  connect() {
    this.table = this.element.querySelector("table")
    const headingRow = this.table?.tHead?.rows[0]
    if (!headingRow) return

    this.headings = [ ...headingRow.cells ]
    this.choices = this.headings
      .map((cell, index) => ({ index, text: headingText(cell), fixed: cell.hasAttribute("data-column-chooser-fixed") }))
      .filter((choice) => !choice.fixed && choice.text !== "")
    if (this.choices.length === 0) return

    // Stored names not on this page (a column shown only sometimes, another
    // page sharing the key) are kept, so saving here doesn't forget them.
    const stored = this.load()
    this.elsewhere = stored.filter((text) => !this.choices.some((choice) => choice.text === text))
    this.hidden = new Set(stored.filter((text) => this.choices.some((choice) => choice.text === text)))
    if (this.choices.every((choice) => this.hidden.has(choice.text))) this.hidden.clear()

    this.menu = this.buildMenu()
    this.place()
    this.apply()
  }

  disconnect() {
    this.placed?.remove()
  }

  toggle(event) {
    const text = event.target.value
    if (event.target.checked) this.hidden.delete(text)
    else this.hidden.add(text)
    this.save()
    this.apply()
  }

  // private

  apply() {
    // Every table inside this element (a report split into sections repeats
    // the same headings), matched by heading text.
    for (const table of this.element.querySelectorAll("table")) {
      const headings = [ ...(table.tHead?.rows[0]?.cells || []) ]
      const hiddenIndexes = new Set(headings
        .map((cell, index) => ({ index, text: headingText(cell), fixed: cell.hasAttribute("data-column-chooser-fixed") }))
        .filter((heading) => !heading.fixed && this.hidden.has(heading.text))
        .map((heading) => heading.index))
      const rows = [ table.tHead, ...table.tBodies, table.tFoot ].filter(Boolean).flatMap((section) => [ ...section.rows ])
      for (const row of rows) {
        if (row.cells.length !== headings.length) continue
        for (const [ index, cell ] of [ ...row.cells ].entries()) cell.classList.toggle("d-none", hiddenIndexes.has(index))
      }
    }

    const boxes = [ ...this.menu.querySelectorAll("input[type=checkbox]") ]
    boxes.forEach((box) => { box.checked = !this.hidden.has(box.value) })
    const ticked = boxes.filter((box) => box.checked)
    boxes.forEach((box) => { box.disabled = ticked.length === 1 && box.checked })
  }

  buildMenu() {
    const wrapper = document.createElement("div")
    wrapper.className = "dropdown no-print"
    wrapper.setAttribute("data-column-chooser-menu", "")

    const button = document.createElement("button")
    button.type = "button"
    button.className = "btn btn-secondary dropdown-toggle"
    button.textContent = "Columns"
    button.setAttribute("data-bs-toggle", "dropdown")
    button.setAttribute("data-bs-auto-close", "outside")
    button.setAttribute("aria-expanded", "false")

    const list = document.createElement("div")
    list.className = "dropdown-menu dropdown-menu-end px-3 py-2"
    this.choices.forEach((choice, position) => {
      const id = `column-chooser-${this.keyValue}-${position}`.replace(/[^\w-]/g, "-")
      const item = document.createElement("div")
      item.className = "form-check text-nowrap"
      const box = document.createElement("input")
      box.type = "checkbox"
      box.className = "form-check-input"
      box.id = id
      box.value = choice.text
      // A listener, not data-action: above the table the menu can sit
      // outside this element (before its scrolling wrapper).
      box.addEventListener("change", (event) => this.toggle(event))
      const label = document.createElement("label")
      label.className = "form-check-label"
      label.htmlFor = id
      label.textContent = choice.text
      item.append(box, label)
      list.append(item)
    })

    wrapper.append(button, list)
    return wrapper
  }

  // Above the table goes outside a scrolling wrapper, so the open menu
  // isn't clipped by it. A copy left in a page Turbo cached is replaced.
  place() {
    if (this.hasSlotTarget) {
      this.slotTarget.querySelectorAll("[data-column-chooser-menu]").forEach((menu) => menu.remove())
      // A slot outside the table actions sits on its own at the right.
      if (!this.slotTarget.closest(".screen-table-actions")) this.menu.classList.add("ms-auto")
      this.slotTarget.append(this.menu)
      this.placed = this.menu
    } else {
      const anchor = this.table.closest(".table-responsive") || this.table
      if (anchor.previousElementSibling?.hasAttribute("data-column-chooser-menu")) anchor.previousElementSibling.remove()
      const row = document.createElement("div")
      row.className = "d-flex justify-content-end mb-2 no-print"
      row.setAttribute("data-column-chooser-menu", "")
      row.append(this.menu)
      anchor.before(row)
      this.placed = row
    }
  }

  get storageKey() {
    return `columns:${this.keyValue}`
  }

  load() {
    try {
      const stored = JSON.parse(window.localStorage.getItem(this.storageKey) || "[]")
      return Array.isArray(stored) ? stored.map(String) : []
    } catch {
      return []
    }
  }

  save() {
    try {
      const names = [ ...this.elsewhere, ...this.hidden ]
      if (names.length === 0) window.localStorage.removeItem(this.storageKey)
      else window.localStorage.setItem(this.storageKey, JSON.stringify(names))
    } catch {
      // Storage may be off (private window); the choice lasts until the page changes.
    }
  }
}
