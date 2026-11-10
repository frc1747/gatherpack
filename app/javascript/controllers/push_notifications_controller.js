import { Controller } from "@hotwired/stimulus"

function keyBytes(base64url) {
  const base64 = base64url.replace(/-/g, "+").replace(/_/g, "/")
  const raw = atob(base64 + "=".repeat((4 - base64.length % 4) % 4))
  return Uint8Array.from(raw, (char) => char.charCodeAt(0))
}

// The "Notify me on this phone" toggle. The browser's permission prompt comes
// only from turning it on, never from loading the page.
export default class extends Controller {
  static targets = ["toggle", "iphone", "blocked", "unsupported", "problem"]
  static values = { url: String, publicKey: String }

  connect() {
    this.turnedOff = () => { if (this.hasToggleTarget) this.toggleTarget.checked = false }
    window.addEventListener("push:unsubscribed", this.turnedOff)
    if (this.hasToggleTarget) this.prepare().catch(() => this.show("unsupported"))
  }

  disconnect() {
    window.removeEventListener("push:unsubscribed", this.turnedOff)
  }

  async prepare() {
    const iphone = /iPhone|iPad|iPod/.test(navigator.userAgent)
    if (iphone && navigator.standalone !== true) return this.show("iphone")
    if (!("serviceWorker" in navigator) || !("PushManager" in window) || !("Notification" in window)) return this.show("unsupported")
    if (Notification.permission === "denied") return this.show("blocked")

    const registration = await navigator.serviceWorker.ready
    this.toggleTarget.checked = Boolean(await registration.pushManager.getSubscription())
    this.toggleTarget.disabled = false
  }

  async toggle() {
    const wanted = this.toggleTarget.checked
    this.toggleTarget.disabled = true
    this.problemTarget.hidden = true

    try {
      const registration = await navigator.serviceWorker.ready
      if (wanted) {
        await this.turnOn(registration)
      } else {
        await this.turnOff(registration)
      }
    } catch {
      this.toggleTarget.checked = !wanted
      this.problemTarget.hidden = false
    }

    this.toggleTarget.disabled = Notification.permission === "denied"
  }

  async turnOn(registration) {
    const permission = await Notification.requestPermission()
    if (permission !== "granted") {
      this.toggleTarget.checked = false
      if (permission === "denied") this.blockedTarget.hidden = false
      return
    }

    const subscription = await registration.pushManager.subscribe({
      userVisibleOnly: true,
      applicationServerKey: keyBytes(this.publicKeyValue)
    })
    const { endpoint, keys } = subscription.toJSON()
    const response = await this.send("POST", { endpoint, p256dh: keys.p256dh, auth: keys.auth })
    if (!response.ok) {
      await subscription.unsubscribe()
      throw new Error("Could not save this device")
    }
  }

  async turnOff(registration) {
    const subscription = await registration.pushManager.getSubscription()
    if (!subscription) return
    await this.send("DELETE", { endpoint: subscription.endpoint })
    await subscription.unsubscribe()
  }

  send(method, body) {
    return fetch(this.urlValue, {
      method,
      headers: {
        "Content-Type": "application/json",
        "Accept": "application/json",
        "X-CSRF-Token": document.querySelector('meta[name="csrf-token"]')?.content
      },
      body: JSON.stringify(body)
    })
  }

  show(state) {
    this[`${state}Target`].hidden = false
  }
}
