import { Controller } from "@hotwired/stimulus"

// A long list of tick boxes opens on the ticked ones plus the first few, with
// "Show all N" revealing the rest in place. The server marks which boxes can
// be hidden; hiding happens here so that everything shows without JavaScript.
// Hidden boxes stay in the form, and a box the browser restored as ticked
// stays visible.
export default class extends Controller {
  static targets = [ "extra", "group", "showAll" ]

  connect() {
    this.extraTargets.forEach((element) => { element.hidden = !element.querySelector("input").checked })
    this.showAllTarget.hidden = !this.extraTargets.some((element) => element.hidden)
    this.hideEmptyGroups()
  }

  showAll() {
    const firstHidden = this.extraTargets.find((element) => element.hidden)
    this.extraTargets.forEach((element) => { element.hidden = false })
    this.showAllTarget.hidden = true
    this.hideEmptyGroups()
    if (firstHidden) firstHidden.querySelector("input").focus()
  }

  hideEmptyGroups() {
    this.groupTargets.forEach((group) => { group.hidden = !group.querySelector(".form-check:not([hidden])") })
  }
}
