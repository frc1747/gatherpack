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

  copyStartDate() {
    if (this.startTarget.value) {
      this.dateTarget.value = this.startTarget.value.slice(0, 10)
    }
  }

  show(timed) {
    this.timeFieldTargets.forEach((field) => { field.hidden = !timed })
    this.dateFieldTargets.forEach((field) => { field.hidden = timed })
  }

  moveTimesToDate() {
    const date = this.dateTarget.value
    if (!date) return

    const start = this.startTarget.value
    const end = this.endTarget.value
    this.startTarget.value = `${date}T${start.slice(11) || "00:00"}`
    if (start && end) {
      this.endTarget.value = `${this.shiftDate(end.slice(0, 10), this.daysBetween(start.slice(0, 10), date))}T${end.slice(11)}`
    }
  }

  // Date-only strings parse as UTC, so daylight saving can't change the count.
  daysBetween(from, to) {
    return Math.round((Date.parse(to) - Date.parse(from)) / 86400000)
  }

  shiftDate(date, days) {
    const shifted = new Date(date)
    shifted.setUTCDate(shifted.getUTCDate() + days)
    return shifted.toISOString().slice(0, 10)
  }

  get timed() {
    return this.kindTargets.find((kind) => kind.checked)?.value === "timed"
  }
}
