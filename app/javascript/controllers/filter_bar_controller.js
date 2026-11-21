import { Controller } from "@hotwired/stimulus"

// A filter bar that shows its choice as soon as it's made: a change to a
// field or the team select submits the form. Show is hidden only once this
// runs, so without JavaScript it stays and still works. Fields under "More
// choices" wait for Show, which stays visible when there are any.
export default class extends Controller {
  static targets = [ "show" ]

  connect() {
    if (!this.element.querySelector("details")) this.showTargets.forEach((button) => { button.hidden = true })
  }

  submit(event) {
    if (event.target.closest("details")) return
    this.element.requestSubmit()
  }
}
