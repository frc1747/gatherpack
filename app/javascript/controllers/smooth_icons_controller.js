import { Controller } from "@hotwired/stimulus"

// Font Awesome turns each <i> into an <svg> on the page, but the server sends
// <i>. Turbo never pairs elements with different tags, so a morph would remove
// and redraw every icon. Converting the incoming page first lets it compare
// <svg> to <svg> and leave the icons alone.
//
// Connects to data-controller="smooth-icons"
export default class extends Controller {
  async convert(event) {
    if (event.detail.renderMethod !== "morph") return

    event.preventDefault()
    try {
      await window.FontAwesome.dom.i2svg({ node: event.detail.newBody })
    } catch (error) {
      console.warn("Icons were not prepared for this page update", error)
    } finally {
      event.detail.resume()
    }
  }
}
