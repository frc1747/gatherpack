import { Controller } from "@hotwired/stimulus"

// A large − / + around a number field (inventory's quantity entry).
export default class extends Controller {
  static targets = ["input"]
  static values = { min: { type: Number, default: 0 } }

  decrement() {
    this.step(-1)
  }

  increment() {
    this.step(1)
  }

  step(by) {
    const current = parseInt(this.inputTarget.value, 10)
    const next = Math.max(this.minValue, (Number.isNaN(current) ? this.minValue : current) + by)
    this.inputTarget.value = next
    this.inputTarget.dispatchEvent(new Event("input", { bubbles: true }))
  }
}
