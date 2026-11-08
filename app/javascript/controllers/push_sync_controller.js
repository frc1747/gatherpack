import { Controller } from "@hotwired/stimulus"

// Tells the server which device this is, once per page load per person. The
// server never attaches a device here; if the subscription isn't this person's,
// the browser drops it. This never asks for permission.
export default class extends Controller {
  static values = { url: String, user: String }

  connect() {
    if (window.pushSyncedFor === this.userValue) return
    window.pushSyncedFor = this.userValue
    this.sync().catch(() => {})
  }

  async sync() {
    if (!("serviceWorker" in navigator)) return
    const registration = await navigator.serviceWorker.getRegistration()
    const subscription = await registration?.pushManager?.getSubscription()
    if (!subscription) return

    const response = await fetch(this.urlValue, {
      method: "POST",
      headers: {
        "Content-Type": "application/json",
        "Accept": "application/json",
        "X-CSRF-Token": document.querySelector('meta[name="csrf-token"]')?.content
      },
      body: JSON.stringify({ endpoint: subscription.endpoint })
    })
    if (!response.ok) return

    const { known } = await response.json()
    if (!known) {
      await subscription.unsubscribe()
      window.dispatchEvent(new Event("push:unsubscribed"))
    }
  }
}
