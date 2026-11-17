import { Controller } from "@hotwired/stimulus"

// Connects to data-controller="print"
export default class extends Controller {
  print() {
    window.print()
  }
}
