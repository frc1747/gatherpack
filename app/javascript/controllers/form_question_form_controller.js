import { Controller } from "@hotwired/stimulus"

// On the form question form: a question linked to a person field takes its
// type from the field, so its own type settings are hidden, and the profile
// mode only shows when a field is linked.
export default class extends Controller {
  static targets = [ "personField", "ownType", "profileMode" ]

  connect() {
    this.update()
  }

  update() {
    if (!this.hasPersonFieldTarget) return
    const linked = this.personFieldTarget.value !== ""
    this.ownTypeTargets.forEach((element) => { element.hidden = linked })
    this.profileModeTargets.forEach((element) => { element.hidden = !linked })
  }
}
