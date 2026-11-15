import { Controller } from "@hotwired/stimulus"

// Connects to data-controller="auto-submit"
// Submits the form shortly after the user stops typing.
export default class extends Controller {
  static values = { delay: { type: Number, default: 250 } }

  submit() {
    clearTimeout(this.timeout)
    this.timeout = setTimeout(() => this.element.requestSubmit(), this.delayValue)
  }

  disconnect() {
    clearTimeout(this.timeout)
  }
}
