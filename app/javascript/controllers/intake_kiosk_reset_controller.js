import { Controller } from "@hotwired/stimulus"

// Clears the registration kiosk after a stretch with nothing happening, and
// a few seconds after the thank-you screen, so the next person starts fresh.
export default class extends Controller {
  static values = { seconds: Number, url: String, after: Number }

  connect() {
    this.reset = this.reset.bind(this)
    this.events = ["keydown", "pointerdown", "input"]
    this.events.forEach((name) => document.addEventListener(name, this.reset))
    this.reset()
  }

  disconnect() {
    this.events.forEach((name) => document.removeEventListener(name, this.reset))
    clearTimeout(this.timer)
  }

  reset() {
    clearTimeout(this.timer)
    const seconds = this.hasAfterValue ? this.afterValue : this.secondsValue
    this.timer = setTimeout(() => window.location.replace(this.urlValue), seconds * 1000)
  }
}
