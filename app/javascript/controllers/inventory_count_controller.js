import { Controller } from "@hotwired/stimulus"

// Count this place: one item per screen, then a summary of the differences
// before saving. Without JavaScript every item shows at once.
export default class extends Controller {
  static targets = ["step", "summary", "differences", "back", "next", "save", "progress"]

  connect() {
    this.index = 0
    this.show()
  }

  next(event) {
    event?.preventDefault()
    if (this.index < this.stepTargets.length) this.index++
    this.show()
  }

  back(event) {
    event?.preventDefault()
    if (this.index > 0) this.index--
    this.show()
  }

  // Enter in a number field goes on to the next item instead of saving.
  enter(event) {
    if (this.index < this.stepTargets.length) this.next(event)
  }

  show() {
    const total = this.stepTargets.length
    const atSummary = this.index >= total
    this.stepTargets.forEach((step, i) => { step.hidden = i !== this.index })
    this.summaryTarget.hidden = !atSummary
    this.backTarget.hidden = this.index === 0
    this.nextTarget.hidden = atSummary
    this.saveTarget.hidden = !atSummary
    if (this.hasProgressTarget) {
      this.progressTarget.textContent = atSummary ? "Check and save" : `${this.index + 1} of ${total}`
    }
    if (atSummary) {
      this.renderSummary()
    } else {
      this.stepTargets[this.index].querySelector("input")?.focus()
    }
  }

  renderSummary() {
    const list = this.differencesTarget
    list.replaceChildren()
    let matched = 0
    let skipped = 0
    this.stepTargets.forEach((step) => {
      const value = step.querySelector("input").value.trim()
      if (value === "") { skipped++; return }
      const seen = parseInt(value, 10)
      const current = parseInt(step.dataset.current, 10)
      if (seen === current) { matched++; return }
      const item = document.createElement("li")
      item.className = "list-group-item d-flex justify-content-between"
      const name = document.createElement("span")
      name.textContent = `${step.dataset.name}: ${current} → ${seen}`
      const difference = document.createElement("strong")
      const change = seen - current
      difference.textContent = change > 0 ? `+${change}` : `${change}`
      item.append(name, difference)
      list.append(item)
    })
    const notes = []
    if (list.children.length === 0) notes.push("No differences.")
    if (matched > 0) notes.push(`${matched} matched.`)
    if (skipped > 0) notes.push(`${skipped} not counted.`)
    const note = document.createElement("li")
    note.className = "list-group-item text-body-secondary"
    note.textContent = notes.join(" ")
    list.append(note)
  }
}
