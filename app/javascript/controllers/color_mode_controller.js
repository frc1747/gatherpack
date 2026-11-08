import { Controller } from "@hotwired/stimulus"

// The Light/Dark/Auto buttons. An empty saved value means Auto, which follows
// the device.
export default class extends Controller {
  static targets = ["button"]
  static values = { url: String, saved: String }

  connect() {
    this.media = window.matchMedia("(prefers-color-scheme: dark)")
    this.followDevice = () => this.apply()
    this.media.addEventListener("change", this.followDevice)
    this.highlight()
  }

  disconnect() {
    this.media.removeEventListener("change", this.followDevice)
  }

  choose({ params: { mode } }) {
    this.savedValue = mode === "auto" ? "" : mode
    this.apply()
    this.highlight()
    // Older cached pages carry the previous choice in their head script.
    window.Turbo?.cache.clear()
    fetch(this.urlValue, {
      method: "PATCH",
      headers: {
        "Content-Type": "application/json",
        "X-CSRF-Token": document.querySelector("meta[name=csrf-token]")?.content
      },
      body: JSON.stringify({ color_mode: mode })
    })
  }

  apply() {
    const mode = this.savedValue || (this.media.matches ? "dark" : "light")
    document.documentElement.setAttribute("data-bs-theme", mode)
  }

  highlight() {
    const current = this.savedValue || "auto"
    this.buttonTargets.forEach((button) => {
      const pressed = button.dataset.colorModeModeParam === current
      button.classList.toggle("active", pressed)
      button.setAttribute("aria-pressed", pressed)
    })
  }
}
