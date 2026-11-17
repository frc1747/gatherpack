import { Controller } from "@hotwired/stimulus"

// Connects to data-controller="reload-on-restore"
// Back can restore this page from the browser's back-forward cache, without a
// request. Reloading fetches it again, without whatever was only meant to show once.
export default class extends Controller {
  reload(event) {
    if (event.persisted) window.location.reload()
  }
}
