import { Controller } from "@hotwired/stimulus"

// Inventory search: searches as the person types, a moment after they stop.
export default class extends Controller {
  static targets = ["input"]

  connect() {
    const input = this.inputTarget
    input.focus()
    input.setSelectionRange(input.value.length, input.value.length)
  }

  search() {
    clearTimeout(this.timer)
    this.timer = setTimeout(() => this.element.requestSubmit(), 300)
  }

  disconnect() {
    clearTimeout(this.timer)
  }
}
