import { Controller } from "@hotwired/stimulus"

// Connects to data-controller="signup-position-kind"
// Shows the unit field only when the position is for items.
export default class extends Controller {
  static targets = ["unit"]

  connect() {
    this.toggle()
  }

  toggle() {
    const kind = this.element.querySelector("input[name='signup_position[kind]']:checked")
    this.unitTarget.hidden = kind?.value !== "items"
  }
}
