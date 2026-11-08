import { Controller } from "@hotwired/stimulus"

// Android offers its own install prompt, saved here until someone asks for it.
let installPrompt = null
window.addEventListener("beforeinstallprompt", (event) => {
  event.preventDefault()
  installPrompt = event
})
window.addEventListener("appinstalled", () => { installPrompt = null })

const IPHONE_STEPS = "In Safari, tap Share, then Add to Home Screen."
const OTHER_STEPS = "In your browser's menu, choose Add to Home screen."

// Shown only in a browser tab on a phone, never once installed.
export default class extends Controller {
  static targets = ["steps"]

  connect() {
    const installed = window.matchMedia("(display-mode: standalone)").matches || window.navigator.standalone === true
    const phone = window.matchMedia("(max-width: 767.98px) and (pointer: coarse)").matches
    this.element.hidden = installed || !phone
  }

  async install() {
    if (installPrompt) {
      const prompt = installPrompt
      installPrompt = null
      prompt.prompt()
      await prompt.userChoice
    } else {
      this.stepsTarget.textContent = /iPhone|iPad|iPod/.test(navigator.userAgent) ? IPHONE_STEPS : OTHER_STEPS
      this.stepsTarget.hidden = false
    }
  }
}
