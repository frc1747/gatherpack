import { Controller } from "@hotwired/stimulus"

// The receive dialog's Inventory fields (orders spec §5). Shows them while
// Track this item is ticked, and keeps "How many go into stock?" at the
// delivery's quantity × pieces per unit until the person types their own.
export default class extends Controller {
  static targets = ["putAway", "fields", "quantity", "stockBox", "summary"]
  static values = { per: Number, lineUnit: String, stockUnit: String, tracked: Boolean, itemName: String }

  connect() {
    this.ownNumber = false
    this.deliveryQuantity = this.element.closest("form")?.querySelector("[name='order_delivery[quantity]']")
    this.onQuantity = () => this.update()
    this.deliveryQuantity?.addEventListener("input", this.onQuantity)
    this.update()
  }

  disconnect() {
    this.deliveryQuantity?.removeEventListener("input", this.onQuantity)
  }

  toggle() {
    this.fieldsTarget.hidden = !this.putAwayTarget.checked
  }

  typed() {
    this.ownNumber = true
  }

  // A linked item from "Which item is it?".
  picked(event) {
    const item = event.detail
    this.trackedValue = item.tracked
    this.itemNameValue = item.name
    this.stockUnitValue = item.unit || this.stockUnitValue
    this.update()
  }

  update() {
    const count = Math.max(parseInt(this.deliveryQuantity?.value, 10) || 0, 0)
    const pieces = count * Math.max(this.perValue, 1)
    if (!this.ownNumber && this.hasQuantityTarget) this.quantityTarget.value = pieces
    this.stockBoxTarget.hidden = this.trackedValue
    this.summaryTarget.textContent = this.trackedValue ? `Adds ${pieces} ${pieces === 1 ? "unit" : "units"} of ${this.itemNameValue}; label them later.` : this.conversion(count, pieces)
  }

  conversion(count, pieces) {
    const each = `${pieces} ${this.stockUnitValue}`
    if (this.perValue <= 1) return each
    const unit = this.lineUnitValue || "unit"
    return `${count} ${count === 1 ? unit : `${unit}s`} = ${each}`
  }
}
