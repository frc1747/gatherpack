import { Controller } from "@hotwired/stimulus"

// Each page's <meta name="gp-color-mode"> says light, dark or auto. Turbo
// replaces that meta on every visit, but only runs a head script whose text
// is new, so the mode has to be applied from the meta on each render. Pages
// without the skin have no meta and are left alone.
const deviceDark = window.matchMedia("(prefers-color-scheme: dark)")

function pageMode() {
  return document.querySelector("meta[name=gp-color-mode]")
}

function applyPageMode() {
  const meta = pageMode()
  if (!meta) return

  const mode = meta.content === "auto" ? (deviceDark.matches ? "dark" : "light") : meta.content
  document.documentElement.setAttribute("data-bs-theme", mode)
}

// This module can finish importing after the first turbo:load has fired.
applyPageMode()
document.addEventListener("turbo:load", applyPageMode)
document.addEventListener("turbo:render", applyPageMode)
deviceDark.addEventListener("change", applyPageMode)

// The Light/Dark/Auto buttons.
export default class extends Controller {
  static targets = ["button"]
  static values = { url: String }

  connect() {
    this.highlight()
  }

  choose({ params: { mode } }) {
    // Written to the meta so this page's Turbo snapshot keeps the new choice.
    pageMode().content = mode
    applyPageMode()
    this.highlight()
    // Older cached pages still carry the previous choice.
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

  highlight() {
    const current = pageMode().content
    this.buttonTargets.forEach((button) => {
      const pressed = button.dataset.colorModeModeParam === current
      button.classList.toggle("active", pressed)
      button.setAttribute("aria-pressed", pressed)
    })
  }
}
