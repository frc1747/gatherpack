import { Controller } from "@hotwired/stimulus"

// The order request form (spec §3.16). A draft saves itself a moment after
// the requester stops typing; Submit for approval waits for a save that's
// under way. A pasted link picks the store from the vendors' domains and
// fills the store part number where the vendor has a pattern; an unknown
// host becomes "Other store". Nothing is fetched from the link.
export default class extends Controller {
  static targets = ["lines", "template", "status", "neededBy", "pickDate", "eventPick"]
  static values = {
    autosave: Boolean,
    vendors: Array,
    events: Object,
    delay: { type: Number, default: 800 }
  }

  connect() {
    this.saving = null
    this.dirty = false
    this.submitting = false
    if (window.matchMedia("(min-width: 768px)").matches) this.openDetails(this.element)
  }

  disconnect() {
    clearTimeout(this.timer)
  }

  // -- Autosave ------------------------------------------------------------

  changed(event) {
    if (!this.autosaveValue || this.submitting || event.target.name === "needed_by_pick") return
    this.dirty = true
    clearTimeout(this.timer)
    const now = event.target.type === "file"
    this.timer = setTimeout(() => this.save(), now ? 0 : this.delayValue)
  }

  save() {
    if (this.saving) {
      this.dirty = true
      return this.saving
    }
    this.dirty = false
    this.setStatus("Saving…")
    const files = [...this.element.querySelectorAll("input[type=file]")].filter(input => input.files.length > 0)
    const body = new FormData(this.element)
    this.saving = fetch(this.element.action, {
      method: "POST",
      body,
      headers: { Accept: "application/json", ...this.csrfHeader() },
      credentials: "same-origin"
    })
      .then(async response => {
        const data = await response.json().catch(() => ({}))
        if (response.ok) {
          this.saved(data, files)
        } else {
          this.setStatus(`Not saved yet: ${(data.errors || ["try again"]).join(" ")}`, true)
        }
      })
      .catch(() => this.setStatus("Not saved yet: check your connection.", true))
      .finally(() => {
        this.saving = null
        if (this.dirty && !this.submitting) this.save()
      })
    return this.saving
  }

  csrfToken() {
    return document.querySelector("meta[name=csrf-token]")?.content
  }

  csrfHeader() {
    const token = this.csrfToken()
    return token ? { "X-CSRF-Token": token } : {}
  }

  saved(data, files) {
    if (data.skipped) {
      this.setStatus("")
      return
    }
    if (data.update_url && !this.element.querySelector("input[name=_method]")) {
      // The draft exists now: later saves change it instead of making another.
      this.element.action = data.update_url
      const method = document.createElement("input")
      Object.assign(method, { type: "hidden", name: "_method", value: "patch" })
      this.element.prepend(method)
      // The page's token was made for creating; use the session's token so
      // later saves and Submit aren't refused as forgeries.
      const token = this.csrfToken()
      const field = this.element.querySelector("input[name=authenticity_token]")
      if (token && field) field.value = token
      if (data.edit_url) history.replaceState(history.state, "", data.edit_url)
    }
    Object.entries(data.lines || {}).forEach(([key, id]) => {
      const input = this.field(key, "id")
      if (input) input.value = id
    })
    ;(data.removed || []).forEach(key => this.field(key, "id")?.closest("[data-order-line]")?.remove())
    files.forEach(input => {
      // Saved with the draft; don't send it again with every save.
      input.value = ""
      this.lineData(input.closest("[data-order-line]"), "photo_status").textContent = "Photo saved"
    })
    this.setStatus("Draft saved")
  }

  submit(event) {
    clearTimeout(this.timer)
    this.submitting = true
    if (this.saving) {
      // Let the save finish first, so the draft isn't made twice.
      event.preventDefault()
      const submitter = event.submitter
      this.saving.then(() => this.element.requestSubmit(submitter))
    }
  }

  // Close: the form saves itself, so save anything not saved yet, then go
  // to the link (My requests). Nothing typed means nothing is saved.
  close(event) {
    event.preventDefault()
    const url = event.currentTarget.href
    clearTimeout(this.timer)
    const pending = this.dirty ? this.save() : this.saving
    Promise.resolve(pending).then(() => window.Turbo ? window.Turbo.visit(url) : window.location.assign(url))
  }

  setStatus(text, problem = false) {
    if (!this.hasStatusTarget) return
    this.statusTarget.textContent = text
    this.statusTarget.classList.toggle("text-danger", problem)
    this.statusTarget.classList.toggle("text-muted", !problem)
  }

  // -- Items ---------------------------------------------------------------

  addLine() {
    const key = Date.now().toString()
    this.linesTarget.insertAdjacentHTML("beforeend", this.templateTarget.innerHTML.replaceAll("NEW_LINE", key))
    const line = this.linesTarget.lastElementChild
    if (window.matchMedia("(min-width: 768px)").matches) this.openDetails(line)
    this.renumber()
    this.lineData(line, "url").focus()
  }

  removeLine(event) {
    const line = event.target.closest("[data-order-line]")
    if (this.lineData(line, "id").value) {
      this.lineData(line, "destroy").value = "1"
      line.hidden = true
    } else {
      line.remove()
    }
    this.renumber()
    this.changed(event)
  }

  renumber() {
    const visible = [...this.linesTarget.querySelectorAll("[data-order-line]")].filter(line => !line.hidden)
    visible.forEach((line, index) => {
      line.querySelector("[data-order-line-number]").textContent = `Item ${index + 1}`
    })
  }

  // -- The link box --------------------------------------------------------

  linkChanged(event) {
    const line = event.target.closest("[data-order-line]")
    const url = event.target.value.trim()
    const host = this.hostOf(url)
    if (!host) return

    const choice = this.lineData(line, "vendor_choice")
    const other = this.lineData(line, "other_vendor_name")
    const part = this.lineData(line, "vendor_part_number")
    const vendor = this.vendorFor(host)
    let match
    if (vendor) {
      choice.value = vendor.id
      if (other.dataset.autofilled) this.fill(other, "")
      const number = this.partNumber(vendor, url)
      if (number) {
        this.fill(part, number)
      } else if (part.dataset.autofilled) {
        this.fill(part, "")
      }
      match = number ? `From ${vendor.name} · part ${number}` : `From ${vendor.name}`
    } else {
      choice.value = "other"
      if (!other.value || other.dataset.autofilled) this.fill(other, host)
      if (part.dataset.autofilled) this.fill(part, "")
      match = `Other store: ${other.value}`
    }
    this.showOtherStore(line)
    this.lineData(line, "match").textContent = match
  }

  vendorChosen(event) {
    this.showOtherStore(event.target.closest("[data-order-line]"))
  }

  showOtherStore(line) {
    this.lineData(line, "other_store").hidden = this.lineData(line, "vendor_choice").value !== "other"
  }

  // Fills a field the requester can still change; a later link may replace
  // what it filled, but never what they typed.
  fill(input, value) {
    input.value = value
    if (value) {
      input.dataset.autofilled = "true"
    } else {
      delete input.dataset.autofilled
    }
  }

  hostOf(url) {
    if (!url) return null
    let parsed
    try {
      parsed = new URL(url)
    } catch {
      try {
        parsed = new URL(`https://${url}`)
      } catch {
        return null
      }
    }
    const host = parsed.hostname.toLowerCase().replace(/^www\./, "")
    return host.includes(".") ? host : null
  }

  // The vendor whose domains hold the host or a domain above it.
  vendorFor(host) {
    const parts = host.split(".")
    for (let i = 0; i < parts.length - 1; i++) {
      const candidate = parts.slice(i).join(".")
      const vendor = this.vendorsValue.find(v => (v.domains || []).includes(candidate))
      if (vendor) return vendor
    }
    return null
  }

  partNumber(vendor, url) {
    if (!vendor.pattern) return null
    try {
      const found = new RegExp(vendor.pattern).exec(url)
      return found && found[1] ? found[1] : null
    } catch {
      return null
    }
  }

  // -- Photo ---------------------------------------------------------------

  photoChosen(event) {
    const line = event.target.closest("[data-order-line]")
    const file = event.target.files[0]
    this.lineData(line, "photo_status").textContent = file ? `Photo: ${file.name}` : ""
  }

  // -- Needed by -----------------------------------------------------------

  pickNeededBy(event) {
    const value = event.target.value
    const pick = value === "pick"
    this.pickDateTarget.hidden = !pick
    if (pick) {
      this.neededByTarget.focus()
    } else {
      this.neededByTarget.value = value
      this.changed({ target: this.neededByTarget, type: "change" })
    }
  }

  // The "Before [event]" pick follows the team.
  teamChanged(event) {
    if (!this.hasEventPickTarget) return
    const next = this.eventsValue[event.target.value]
    const radio = this.eventPickTarget.querySelector("input")
    const label = this.eventPickTarget.querySelector("label")
    this.eventPickTarget.hidden = !next
    radio.value = next ? next.date : ""
    label.textContent = next ? next.label : ""
    if (!next && radio.checked) {
      radio.checked = false
      this.neededByTarget.value = ""
    }
  }

  // -- Helpers -------------------------------------------------------------

  field(key, name) {
    return this.element.querySelector(`[name="order_request[lines][${key}][${name}]"]`)
  }

  lineData(line, name) {
    return line.querySelector(`[data-field="${name}"]`)
  }

  openDetails(root) {
    root.querySelectorAll("details[data-more]").forEach(details => { details.open = true })
  }
}
