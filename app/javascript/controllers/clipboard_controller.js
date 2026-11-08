import { Controller } from "@hotwired/stimulus"

// Connects to data-controller="clipboard"
export default class extends Controller {
  static targets = [ "source", "status" ]

  disconnect() {
    clearTimeout(this.clearStatusTimer)
  }

  async copy() {
    clearTimeout(this.clearStatusTimer)

    try {
      await navigator.clipboard.writeText(this.sourceTarget.textContent)
      this.showStatus("Copied", "text-success")
      this.clearStatusTimer = setTimeout(() => this.showStatus("", ""), 3000)
    } catch {
      // navigator.clipboard is undefined outside a secure context, and
      // writeText rejects when the browser refuses. Leave the text ready to copy by hand.
      window.getSelection().selectAllChildren(this.sourceTarget)
      this.showStatus("Couldn't copy automatically. The text is selected, so copy it with your keyboard.", "text-danger")
    }
  }

  showStatus(message, className) {
    this.statusTarget.textContent = message
    this.statusTarget.className = `ms-2 ${className}`.trim()
  }
}
