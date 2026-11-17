import { Controller } from "@hotwired/stimulus"

// Kept outside the controller so a replaced sidebar still opens where the last one was.
let savedScrollTop = 0

// Keeps a permanent sidebar correct between pages.
//
// Connects to data-controller="smooth-sidebar"
export default class extends Controller {
  beforeRender(event) {
    const { newBody, renderMethod } = event.detail
    const incoming = newBody.querySelector(`#${CSS.escape(this.element.id)}`)

    savedScrollTop = this.scroller.scrollTop
    this.nextActiveLinks = incoming && this.activeLinksIn(incoming)

    // A morph never removes a permanent element, so a sidebar the next page
    // doesn't have must stop being permanent or there would be two.
    if (!incoming && renderMethod === "morph") this.element.removeAttribute("data-turbo-permanent")
  }

  // Waits for the render because the page Turbo caches for the Back button is
  // cloned from this sidebar, and has to keep the links active on that page.
  afterRender() {
    // Moving the sidebar into the new page resets its scroll position.
    this.scroller.scrollTop = savedScrollTop

    if (this.nextActiveLinks) {
      this.element.querySelectorAll(".nav-item a").forEach(link => {
        link.classList.toggle("active", this.nextActiveLinks.has(link.getAttribute("href")))
      })
      this.nextActiveLinks = null
    }
  }

  closeOffcanvas() {
    const panel = this.element.querySelector(".offcanvas-md")
    if (panel) window.bootstrap?.Offcanvas.getInstance(panel)?.hide()
  }

  // The server already worked out which links are active for the next page,
  // so its markup is the only copy of those rules.
  activeLinksIn(sidebar) {
    return new Set([ ...sidebar.querySelectorAll("a.active") ].map(link => link.getAttribute("href")))
  }

  get scroller() {
    return this.element.querySelector(".offcanvas-body") || this.element
  }
}
