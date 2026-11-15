import { Controller } from "@hotwired/stimulus"

// Searches inventory items (order_inventory/items.json) as the person types.
// In "line" mode (Pick from what we stock, on the request form) a pick fills
// the first empty item, or adds one, and links it. In "link" mode (the
// receive dialog) a pick sets the hidden item_id. Either way it dispatches
// order-item-search:picked with the item.
export default class extends Controller {
  static targets = ["query", "results", "status", "itemId", "create"]
  static values = { url: String, mode: String, delay: { type: Number, default: 250 } }

  disconnect() {
    clearTimeout(this.timer)
  }

  ignoreEnter(event) {
    event.preventDefault()
  }

  search(event) {
    // The search box isn't part of the form: don't let it start an autosave.
    event.stopPropagation()
    clearTimeout(this.timer)
    if (this.hasItemIdTarget) this.itemIdTarget.value = ""
    const query = this.queryTarget.value.trim()
    if (query.length === 0) {
      this.resultsTarget.replaceChildren()
      return
    }
    this.timer = setTimeout(() => this.fetchItems(query), this.delayValue)
  }

  async fetchItems(query) {
    const url = new URL(this.urlValue, window.location.origin)
    url.searchParams.set("q", query)
    try {
      const response = await fetch(url, { headers: { Accept: "application/json" }, credentials: "same-origin" })
      if (!response.ok) throw new Error(response.statusText)
      this.show(await response.json())
    } catch {
      this.setStatus("Couldn't search: check your connection.")
    }
  }

  show(items) {
    this.items = items
    this.resultsTarget.replaceChildren(...items.map((item, index) => {
      const button = document.createElement("button")
      button.type = "button"
      button.className = "list-group-item list-group-item-action py-2"
      button.dataset.index = index
      button.dataset.action = "order-item-search#pick"
      const name = document.createElement("div")
      name.className = "fw-semibold"
      name.textContent = item.name
      const details = document.createElement("small")
      details.className = "text-muted"
      details.textContent = [item.part_number, `${item.stock} in stock`].filter(Boolean).join(" · ")
      button.append(name, details)
      return button
    }))
    this.setStatus(items.length === 0 ? "Nothing we stock matches." : "")
  }

  pick(event) {
    const item = this.items[Number(event.currentTarget.dataset.index)]
    this.resultsTarget.replaceChildren()
    if (this.modeValue === "line") {
      this.fillLine(item)
      this.queryTarget.value = ""
      this.setStatus(`Added ${item.name}. Change anything below.`)
    } else {
      this.itemIdTarget.value = item.id
      this.queryTarget.value = item.name
      if (this.hasCreateTarget) this.createTarget.checked = false
      this.setStatus(`This is ${item.name}.`)
    }
    this.dispatch("picked", { detail: item })
  }

  // -- Line mode -------------------------------------------------------------

  fillLine(item) {
    const form = this.element.closest("form")
    let line = [...form.querySelectorAll("[data-order-line]")].find(candidate => !candidate.hidden && this.isEmpty(candidate))
    if (!line) {
      form.querySelector("[data-action~='order-form#addLine']").click()
      const lines = form.querySelectorAll("[data-order-line]")
      line = lines[lines.length - 1]
    }
    Object.entries(item.line).forEach(([field, value]) => this.setField(line, field, value))
    if (this.field(line, "vendor_choice")?.value === "other" && !this.field(line, "other_vendor_name").value) {
      this.setField(line, "other_vendor_name", item.vendor_name)
    }
    this.setField(line, "quantity", this.field(line, "quantity")?.value || 1)
    const changed = this.field(line, "description") || this.field(line, "item_id")
    changed.dispatchEvent(new Event("input", { bubbles: true }))
  }

  isEmpty(line) {
    return ["url", "description", "item_id"].every(field => !this.field(line, field)?.value)
  }

  setField(line, field, value) {
    const input = this.field(line, field)
    if (!input) return
    if (field === "vendor_choice" && ![...input.options].some(option => option.value === String(value))) {
      // A vendor the form doesn't list: name it as another store.
      value = "other"
    }
    // Filled from the item: a pasted link may still replace it.
    if (value) input.dataset.autofilled = "true"
    input.value = value ?? ""
    if (field === "vendor_choice") input.dispatchEvent(new Event("change", { bubbles: true }))
  }

  field(line, name) {
    return line.querySelector(`[data-field="${name}"]`) || line.querySelector(`[name$="[${name}]"]`)
  }

  setStatus(text) {
    if (this.hasStatusTarget) this.statusTarget.textContent = text
  }
}
