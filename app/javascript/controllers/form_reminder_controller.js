import { Controller } from "@hotwired/stimulus"

// The Remind screen: "Also email guardians" shows the count, list and
// preview for that choice, and "Use the default" puts a message back to the
// built-in one.
export default class extends Controller {
  static targets = [ "guardians" ]

  toggle() {
    const state = this.guardiansTarget.checked ? "on" : "off"
    this.element.querySelectorAll("[data-form-reminder-when]").forEach((element) => {
      element.hidden = element.dataset.formReminderWhen !== state
    })
  }

  useDefault(event) {
    const field = this.element.querySelector(`textarea[name="${event.target.dataset.field}"]`)
    if (field) field.value = field.dataset.default
  }
}
