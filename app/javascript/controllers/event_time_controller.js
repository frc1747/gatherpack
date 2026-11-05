import { Controller } from "@hotwired/stimulus"

// Connects to data-controller="event-time"
// Without JavaScript every field shows, and the model ignores whichever don't apply.
export default class extends Controller {
  static targets = ["kind", "date", "dateField", "start", "end", "timeField"]

  connect() {
    this.show(this.timed)
  }

  sync() {
    if (this.timed) {
      this.moveTimesToDate()
    } else if (!this.dateTarget.value) {
      this.dateTarget.value = this.startTarget.value.slice(0, 10)
    }
    this.show(this.timed)
  }

  show(timed) {
    this.timeFieldTargets.forEach((field) => { field.hidden = !timed })
    this.dateFieldTargets.forEach((field) => { field.hidden = timed })
  }

  moveTimesToDate() {
    const date = this.dateTarget.value
    if (!date) return

    const start = this.startTarget.value
    this.startTarget.value = `${date}T${start.slice(11) || "00:00"}`
    if (this.endTarget.value) {
      this.endTarget.value = `${date}T${this.endTarget.value.slice(11)}`
    }
  }

  get timed() {
    return this.kindTargets.find((kind) => kind.checked)?.value === "timed"
  }
}
