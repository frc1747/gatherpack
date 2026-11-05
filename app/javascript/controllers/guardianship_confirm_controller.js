import { Controller } from "@hotwired/stimulus"

// Asks for confirmation on submit when the selected guardianship would turn a
// saved type into a guardianship, or stop it being one.
export default class extends Controller {
  static targets = [ "select" ]
  static values = { saved: Boolean, message: String }

  connect() {
    this.update()
  }

  update() {
    const form = this.element.closest("form")
    if ((this.selectTarget.value !== "none") !== this.savedValue) {
      form.dataset.turboConfirm = this.messageValue
    } else {
      delete form.dataset.turboConfirm
    }
  }
}
