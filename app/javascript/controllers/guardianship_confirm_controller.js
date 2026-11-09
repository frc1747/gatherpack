import { Controller } from "@hotwired/stimulus"

// Asks for confirmation on submit when the selected guardianship would turn a
// saved type into a guardianship, or stop it being one, and when ticking "Show
// contact details" would start showing them for the type's relationships.
export default class extends Controller {
  static targets = [ "select", "contactDetails" ]
  static values = { saved: Boolean, message: String, contactDetailsMessage: String }

  connect() {
    this.update()
  }

  update() {
    const form = this.element.closest("form")
    const messages = []
    if (this.messageValue && (this.selectTarget.value !== "none") !== this.savedValue) messages.push(this.messageValue)
    if (this.contactDetailsTarget.checked && this.contactDetailsMessageValue) messages.push(this.contactDetailsMessageValue)

    if (messages.length > 0) {
      form.dataset.turboConfirm = messages.join(" ")
    } else {
      delete form.dataset.turboConfirm
    }
  }
}
