import { Controller } from "@hotwired/stimulus"

// Removes an existing receipt row from the ledger entry form.
export default class extends Controller {
  remove(event) {
    var parent = event.target.parentElement;
    while(!parent.classList.contains('row')) {
      parent = parent.parentElement;
    }
    parent.remove();
  }
}
