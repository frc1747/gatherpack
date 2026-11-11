import { Controller } from "@hotwired/stimulus"

// Saves a form as soon as one of its controls changes.
export default class extends Controller {
  submit() {
    this.element.requestSubmit()
  }
}
