import { Controller } from "@hotwired/stimulus"

// Connects to data-controller="select-all": a checkbox (the all target)
// that ticks or clears every item checkbox.
export default class extends Controller {
  static targets = ["all", "item"]

  toggle() {
    this.itemTargets.forEach((item) => { item.checked = this.allTarget.checked })
  }
}
