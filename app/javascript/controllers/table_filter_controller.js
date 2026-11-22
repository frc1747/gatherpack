import { Controller } from "@hotwired/stimulus"

// Sorting and filtering the tables inside this element by their columns
// (attached with the Columns chooser). Clicking a heading's name sorts each
// table body by that column; again reverses. A funnel beside the name lists
// the column's values with counts across every table here; ticking some
// shows only rows with any of them, and filters on several columns combine.
// Over 12 values, a search box narrows the list. "Clear filters" sits beside
// Columns while any filter is on. Neither is remembered.
// A cell's value: its data-filter-value, else its text; it sorts by its
// data-sort-value, else that value (numbers and dates compared as such).
// Headings with no text or marked data-table-filter-skip, and columns whose
// cells hold form fields, get neither. Inside data-table-filter="off" nothing
// is added. Rows with a different cell count from the headings (separators)
// are never hidden and sort last.
const SEARCH_AFTER = 12
const FIELDS = "input:not([type=hidden]), select, textarea"

function headingText(cell) {
  return (cell.querySelector("[data-column-chooser-label]") || cell).textContent.trim()
}

function cellValue(cell) {
  return (cell.dataset.filterValue ?? cell.textContent).replace(/\s+/g, " ").trim()
}

function sortKey(cell) {
  const text = (cell.dataset.sortValue ?? cellValue(cell)).trim()
  const number = text.replace(/[$,\s]/g, "")
  if (number !== "" && !isNaN(number)) return { number: Number(number), text }
  if (/^\d{4}-\d{2}-\d{2}/.test(text) && !isNaN(Date.parse(text))) return { number: Date.parse(text), text }
  return { text }
}

// Blanks last; numbers (and dates) before text and by size.
function compare(a, b) {
  if ((a.text === "") !== (b.text === "")) return a.text === "" ? 1 : -1
  if (a.number !== undefined && b.number !== undefined) return a.number - b.number
  if ((a.number !== undefined) !== (b.number !== undefined)) return a.number !== undefined ? -1 : 1
  return a.text.localeCompare(b.text, undefined, { numeric: true, sensitivity: "base" })
}

export default class extends Controller {
  connect() {
    if (this.element.closest("[data-table-filter='off']")) return
    this.tables = [ ...this.element.querySelectorAll("table") ]
      .filter((table) => !table.closest("[data-table-filter='off']") && table.tHead?.rows[0])
    if (this.tables.length === 0) return

    // A copy Turbo cached keeps the old controls; start again from the markup.
    this.element.querySelectorAll("[data-table-filter-menu], [data-table-filter-arrow], [data-table-filter-clear]").forEach((node) => node.remove())
    this.anchor = this.tables[0].closest(".table-responsive") || this.tables[0]
    if (this.anchor.previousElementSibling?.matches("[data-table-filter-clear]")) this.anchor.previousElementSibling.remove()
    for (const row of this.bodyRows()) this.show(row, true)

    this.filters = new Map() // heading text -> Set of ticked values
    this.sorted = null
    this.columns = this.findColumns()
    for (const [ text, column ] of this.columns) column.headings.forEach((heading) => this.decorate(heading, text, column))
  }

  disconnect() {
    this.clearLink?.remove()
  }

  // private

  bodyRows(table) {
    return (table ? [ table ] : this.tables).flatMap((t) => [ ...t.tBodies ].flatMap((body) => [ ...body.rows ]))
  }

  // Columns by heading text: their headings, their cell index in each table,
  // and their values with counts (blank as "").
  findColumns() {
    const columns = new Map()
    for (const table of this.tables) {
      const headings = [ ...table.tHead.rows[0].cells ]
      headings.forEach((heading, index) => {
        const text = headingText(heading)
        if (text === "" || heading.hasAttribute("data-table-filter-skip")) return
        const column = columns.get(text) || { headings: [], indexes: new Map(), counts: new Map(), fields: false }
        columns.set(text, column)
        column.headings.push(heading)
        column.indexes.set(table, index)
        for (const row of this.bodyRows(table)) {
          if (row.cells.length !== headings.length) continue
          const cell = row.cells[index]
          if (cell.querySelector(FIELDS)) column.fields = true
          const value = cellValue(cell)
          column.counts.set(value, (column.counts.get(value) || 0) + 1)
        }
      })
    }
    for (const [ text, column ] of columns) if (column.fields) columns.delete(text)
    return columns
  }

  decorate(heading, text, column) {
    let label = heading.querySelector("[data-column-chooser-label]")
    if (!label) {
      label = document.createElement("span")
      label.setAttribute("data-column-chooser-label", "")
      label.setAttribute("data-table-filter-label", "")
      const nodes = [ ...heading.childNodes ].filter((node) => !(node.nodeType === Node.ELEMENT_NODE && node.matches("a, button, .dropdown, " + FIELDS)))
      heading.prepend(label)
      label.append(...nodes)
    }
    // A heading whose name is a link (a server-side sort) keeps only that.
    if (label.textContent.trim() !== "") {
      label.setAttribute("role", "button")
      label.tabIndex = 0
      label.onclick = () => this.sort(text)
      label.onkeydown = (event) => {
        if (event.key !== "Enter" && event.key !== " ") return
        event.preventDefault()
        this.sort(text)
      }
    }
    // Icons are redrawn, not restyled: Font Awesome swaps each <i> for an <svg>.
    const arrow = document.createElement("span")
    arrow.className = "ms-1"
    arrow.setAttribute("data-table-filter-arrow", "")
    arrow.setAttribute("aria-hidden", "true")
    label.after(arrow)
    arrow.after(this.buildMenu(text, column))
  }

  buildMenu(text, column) {
    const wrapper = document.createElement("div")
    wrapper.className = "dropdown d-inline no-print"
    wrapper.setAttribute("data-table-filter-menu", text)

    const button = document.createElement("button")
    button.type = "button"
    // The heading's own colour: dimmed while off, full while it filters.
    button.className = "btn btn-link btn-sm p-0 ms-1 text-reset opacity-50"
    button.setAttribute("data-bs-toggle", "dropdown")
    button.setAttribute("data-bs-auto-close", "outside")
    // Fixed, so a scrolling table wrapper doesn't clip the open menu.
    button.setAttribute("data-bs-popper-config", '{"strategy":"fixed"}')
    button.setAttribute("aria-expanded", "false")
    button.setAttribute("aria-label", `Filter ${text}`)
    button.innerHTML = '<i class="fa-solid fa-filter"></i>'

    const menu = document.createElement("div")
    menu.className = "dropdown-menu p-2 small fw-normal text-start"
    const key = (value) => sortKey({ dataset: { sortValue: value } })
    const values = [ ...column.counts.keys() ].sort((a, b) => compare(key(a), key(b)))
    const items = values.map((value) => {
      const item = document.createElement("label")
      item.className = "d-block text-nowrap"
      const box = document.createElement("input")
      box.type = "checkbox"
      box.className = "form-check-input me-1"
      box.value = value
      box.setAttribute("data-table-filter-tick", text)
      box.addEventListener("change", () => this.tick(text, value, box.checked))
      const count = document.createElement("span")
      count.className = "text-body-secondary"
      count.textContent = `(${column.counts.get(value)})`
      item.append(box, `${value === "" ? "(blank)" : value} `, count)
      return item
    })
    if (values.length > SEARCH_AFTER) {
      const search = document.createElement("input")
      search.type = "search"
      search.className = "form-control form-control-sm mb-2"
      search.placeholder = "Search…"
      search.setAttribute("aria-label", `Search ${text}`)
      search.addEventListener("input", () => {
        const query = search.value.trim().toLowerCase()
        items.forEach((item) => item.classList.toggle("d-none", query !== "" && !item.textContent.toLowerCase().includes(query)))
      })
      menu.append(search)
    }
    menu.append(...items)
    wrapper.append(button, menu)
    return wrapper
  }

  tick(text, value, checked) {
    const ticked = this.filters.get(text) || new Set()
    if (checked) ticked.add(value)
    else ticked.delete(value)
    if (ticked.size === 0) this.filters.delete(text)
    else this.filters.set(text, ticked)
    this.apply()
  }

  clear() {
    this.filters.clear()
    this.apply()
  }

  apply() {
    // Every menu for the column (one per table) shows the same ticks.
    for (const box of this.element.querySelectorAll("[data-table-filter-tick]")) {
      box.checked = this.filters.get(box.dataset.tableFilterTick)?.has(box.value) || false
    }
    for (const [ text, column ] of this.columns) {
      for (const heading of column.headings) {
        const button = heading.querySelector("[data-table-filter-menu] > button")
        button.classList.toggle("opacity-50", !this.filters.has(text))
      }
    }
    for (const table of this.tables) {
      const width = table.tHead.rows[0].cells.length
      for (const row of this.bodyRows(table)) {
        if (row.cells.length !== width) continue
        this.show(row, [ ...this.filters ].every(([ text, ticked ]) => {
          const index = this.columns.get(text).indexes.get(table)
          return index === undefined || ticked.has(cellValue(row.cells[index]))
        }))
      }
    }
    this.placeClearLink()
    this.clearLink.hidden = this.filters.size === 0
  }

  show(row, shown) {
    row.hidden = !shown
    row.classList.toggle("table-filter-hidden", !shown)
  }

  sort(text) {
    const ascending = !(this.sorted?.text === text && this.sorted.ascending)
    this.sorted = { text, ascending }
    for (const table of this.tables) {
      const index = this.columns.get(text).indexes.get(table)
      if (index === undefined) continue
      const width = table.tHead.rows[0].cells.length
      for (const body of table.tBodies) {
        const rows = [ ...body.rows ]
        const sortable = rows.filter((row) => row.cells.length === width)
        sortable.sort((a, b) => (ascending ? 1 : -1) * compare(sortKey(a.cells[index]), sortKey(b.cells[index])))
        body.append(...sortable, ...rows.filter((row) => row.cells.length !== width))
      }
    }
    for (const [ name, column ] of this.columns) {
      for (const heading of column.headings) {
        const arrow = heading.querySelector("[data-table-filter-arrow]")
        arrow.innerHTML = name === text ? `<i class="fa-solid fa-arrow-${ascending ? "up" : "down"}"></i>` : ""
        if (name === text) heading.setAttribute("aria-sort", ascending ? "ascending" : "descending")
        else heading.removeAttribute("aria-sort")
      }
    }
  }

  // Right after the Columns dropdown: in the filter bar's slot, or in the
  // row the chooser puts above the table; else in a row of its own there.
  placeClearLink() {
    if (this.clearLink?.isConnected) return
    const link = this.clearLink = document.createElement("a")
    link.href = "#"
    link.className = "ms-2 align-self-center text-nowrap no-print"
    link.textContent = "Clear filters"
    link.setAttribute("role", "button")
    link.setAttribute("data-table-filter-clear", "")
    link.addEventListener("click", (event) => {
      event.preventDefault()
      this.clear()
    })

    const anchor = this.anchor
    const chooser = this.element.querySelector("[data-column-chooser-target=slot] [data-column-chooser-menu]") ||
      (anchor.previousElementSibling?.matches("[data-column-chooser-menu]") && anchor.previousElementSibling.querySelector(".dropdown"))
    if (chooser) {
      chooser.after(link)
    } else {
      const row = document.createElement("div")
      row.className = "d-flex justify-content-end mb-2 no-print"
      row.setAttribute("data-table-filter-clear", "")
      row.append(link)
      anchor.before(row)
    }
  }
}
