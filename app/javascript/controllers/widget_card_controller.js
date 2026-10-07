import { Controller } from "@hotwired/stimulus"

// A dashboard widget's card. It stays hidden until its body loads, and
// stays hidden if the body comes back empty (the widget has nothing to show
// this person). Reloads the body every `refresh` seconds while the page is
// on screen.
export default class extends Controller {
  static targets = [ "frame" ]
  static values = { refresh: Number }

  connect() {
    this.onLoad = this.onLoad.bind(this)
    this.element.addEventListener("turbo:frame-load", this.onLoad)

    if (this.refreshValue > 0) {
      this.timer = setInterval(() => {
        if (document.visibilityState === "visible") this.frameTarget.reload()
      }, this.refreshValue * 1000)
    }
  }

  disconnect() {
    this.element.removeEventListener("turbo:frame-load", this.onLoad)
    clearInterval(this.timer)
  }

  onLoad() {
    this.element.hidden = this.frameTarget.querySelector(".widget-body") === null
  }
}
