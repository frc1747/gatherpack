import { Controller } from "@hotwired/stimulus"
import { Turbo } from "@hotwired/turbo-rails"

// Sends the time kiosk back to the Welcome screen after a number of seconds
// without a tap or key press. While a modal is open the countdown pauses, but
// only for so long, so a manager window can't be left open on a shared screen.
export default class extends Controller {
  static targets = ["message"]
  static values = { seconds: Number, url: String }

  connect() {
    this.area = this.element.closest("#kiosk-content") || document.body
    this.restart = this.restart.bind(this)
    this.tick = this.tick.bind(this)
    this.area.addEventListener("pointerdown", this.restart)
    this.area.addEventListener("keydown", this.restart)

    this.restart()
    this.lastTick = Date.now()
    this.interval = setInterval(this.tick, 250)
  }

  disconnect() {
    clearInterval(this.interval)
    this.interval = null
    this.area.removeEventListener("pointerdown", this.restart)
    this.area.removeEventListener("keydown", this.restart)
  }

  restart() {
    this.remaining = this.secondsValue * 1000
    this.lastInput = Date.now()
    this.render()
  }

  tick() {
    const now = Date.now()
    const elapsed = now - this.lastTick
    this.lastTick = now

    const modal = this.openModal()
    if (modal) {
      if (now - this.lastInput >= this.modalLimit * 1000) {
        window.bootstrap?.Modal.getInstance(modal)?.hide()
        this.goHome()
      } else {
        this.render(true)
      }
      return
    }

    this.remaining -= elapsed
    if (this.remaining <= 0) {
      this.goHome()
    } else {
      this.render()
    }
  }

  // Scans arrive as Turbo Streams, so the kiosk URL's cached snapshot is an
  // earlier person's profile. Drop it and keep this one out of the cache, or
  // the visit would preview someone else's screen. Replace, so returns don't
  // pile up history entries.
  goHome() {
    this.disconnect()
    Turbo.cache.clear()
    Turbo.cache.exemptPageFromCache()
    Turbo.visit(this.urlValue, { action: "replace" })
  }

  render(paused = false) {
    if (this.hasMessageTarget) {
      this.messageTarget.textContent = paused ? "Paused" : `Returning in ${Math.max(Math.ceil(this.remaining / 1000), 0)}s`
    }
  }

  openModal() {
    return this.area.querySelector(".modal.show")
  }

  get modalLimit() {
    return Math.max(this.secondsValue, 60)
  }
}
