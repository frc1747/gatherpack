import { Controller } from "@hotwired/stimulus"

// Fades a time kiosk confirmation ("Sam clocked out.") after a few seconds,
// so the next person sees a clean Welcome screen.
export default class extends Controller {
  static values = { seconds: { type: Number, default: 6 } }

  connect() {
    this.timeout = setTimeout(() => this.dismiss(), this.secondsValue * 1000)
  }

  disconnect() {
    clearTimeout(this.timeout)
  }

  dismiss() {
    const alert = window.bootstrap?.Alert.getOrCreateInstance(this.element)
    if (alert) {
      alert.close()
    } else {
      this.element.remove()
    }
  }
}
