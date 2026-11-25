import { Controller } from "@hotwired/stimulus"

// Asks for confirmation before a form submits, for forms Turbo doesn't
// handle (data-turbo="false"), where data-turbo-confirm never fires.
//
//   <form data-controller="submit-confirm" data-action="submit->submit-confirm#confirm"
//         data-submit-confirm-message-value="Are you sure?">
export default class extends Controller {
  static values = { message: String }

  confirm(event) {
    if (this.messageValue && !window.confirm(this.messageValue)) {
      event.preventDefault()
      event.stopImmediatePropagation()
    }
  }
}
