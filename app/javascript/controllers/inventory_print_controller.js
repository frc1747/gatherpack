import { Controller } from "@hotwired/stimulus"

// Print button on an inventory page; the page's print styles do the rest.
export default class extends Controller {
  print() {
    window.print()
  }
}
