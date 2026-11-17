import { Controller } from "@hotwired/stimulus"

// "Who this passes": posts the draft form to the preview URL a moment after
// the last change and shows the answer, so nothing is saved.
export default class extends Controller {
  static targets = ["form", "output", "spinner"]
  static values = { url: String }

  connect() {
    this.refresh = this.refresh.bind(this)
    this.form.addEventListener("input", this.refresh)
    this.form.addEventListener("change", this.refresh)
  }

  disconnect() {
    this.form.removeEventListener("input", this.refresh)
    this.form.removeEventListener("change", this.refresh)
    clearTimeout(this.timer)
  }

  get form() {
    return this.hasFormTarget ? this.formTarget : this.element
  }

  refresh() {
    clearTimeout(this.timer)
    this.timer = setTimeout(() => this.load(), 400)
  }

  async load() {
    const body = new FormData(this.form)
    body.delete("_method")
    const token = document.querySelector("meta[name='csrf-token']")?.content
    if (this.hasSpinnerTarget) this.spinnerTarget.classList.remove("d-none")
    try {
      const response = await fetch(this.urlValue, { method: "POST", body, headers: { "X-CSRF-Token": token, "Accept": "text/html" } })
      if (response.ok) this.outputTarget.innerHTML = await response.text()
    } finally {
      if (this.hasSpinnerTarget) this.spinnerTarget.classList.add("d-none")
    }
  }
}
