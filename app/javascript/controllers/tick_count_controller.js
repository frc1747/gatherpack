import { Controller } from "@hotwired/stimulus"

// Keeps a question's count in step with the ticked boxes, as in Bill people's
// "Create 2 invoices in QuickBooks?". The server writes the count for the
// boxes as drawn, so the words are right without JavaScript until a box is
// ticked or unticked.
export default class extends Controller {
  static targets = [ "box", "count", "noun" ]
  static values = { one: String, many: String }

  update() {
    const count = this.boxTargets.filter((box) => box.checked).length
    this.countTargets.forEach((element) => { element.textContent = count })
    this.nounTargets.forEach((element) => { element.textContent = count === 1 ? this.oneValue : this.manyValue })
  }
}
