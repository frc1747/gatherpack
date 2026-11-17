import { Controller } from "@hotwired/stimulus"

// The values of a profile field test: shows the ticks for the field picked
// when it's a choice field, and the text to type into otherwise. What's
// hidden is disabled, so it isn't posted.
export default class extends Controller {
  static targets = ["choices", "text"]
  static values = { field: String }

  connect() {
    this.select = document.getElementById(this.fieldValue)
    this.select?.addEventListener("change", this.show)
    this.show()
  }

  disconnect() {
    this.select?.removeEventListener("change", this.show)
  }

  show = () => {
    const chosen = this.select?.value
    let found = false
    this.choicesTargets.forEach((fieldset) => {
      const on = fieldset.dataset.fieldId === chosen
      found ||= on
      fieldset.classList.toggle("d-none", !on)
      fieldset.disabled = !on
    })
    this.textTarget.classList.toggle("d-none", found)
    this.textTarget.querySelector("input").disabled = found
  }
}
