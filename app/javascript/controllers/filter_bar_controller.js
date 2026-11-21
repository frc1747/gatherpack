import { Controller } from "@hotwired/stimulus"

// A filter bar that shows its choice as soon as it's made. A change under
// "More choices" always submits the form; with auto (the bar's auto_submit:)
// a change to a field or the team select does too, and the top-row Show is
// hidden once this runs, so without JavaScript it stays and still works. It
// also stays while More choices is there. Text boxes fire change on leaving
// them (or Enter submits), not on each key.
export default class extends Controller {
  static targets = [ "show" ]
  static values = { auto: Boolean }

  connect() {
    if (this.autoValue && !this.element.querySelector("details")) this.showTargets.forEach((button) => { button.hidden = true })
  }

  submit(event) {
    if (!this.autoValue && !event.target.closest("details")) return
    this.element.requestSubmit()
  }
}
