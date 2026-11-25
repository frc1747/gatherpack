import { Controller } from "@hotwired/stimulus"

// Connects to data-controller="choice-settings"
// Radio choices with their settings inline: each settings target belongs to
// one choice of one radio group (data-group, data-choice) and shows only
// while that choice is picked. Hidden settings are disabled, so they aren't
// sent with the form.
export default class extends Controller {
  static targets = [ "settings" ]

  connect() {
    this.show()
  }

  show() {
    this.settingsTargets.forEach((element) => {
      const picked = this.element.querySelector(`input[type=radio][data-group="${element.dataset.group}"]:checked`)
      const shown = picked?.value === element.dataset.choice
      element.hidden = !shown
      element.querySelectorAll("input, select, textarea").forEach((input) => { input.disabled = !shown })
    })
  }
}
