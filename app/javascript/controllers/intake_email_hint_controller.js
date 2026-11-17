import { Controller } from "@hotwired/stimulus"

// "Did you mean gmail.com?" for an email domain one or two letters off a
// common one. Only a hint: the address is sent as typed.
export default class extends Controller {
  static targets = ["input", "hint"]
  static values = { domains: Array }

  check() {
    const [name, domain] = this.inputTarget.value.trim().toLowerCase().split("@")
    const suggestion = domain && !this.domainsValue.includes(domain) &&
      this.domainsValue.find((known) => this.distance(domain, known) <= 2)

    if (suggestion) {
      this.hintTarget.textContent = `Did you mean ${name}@${suggestion}?`
      this.hintTarget.hidden = false
    } else {
      this.hintTarget.hidden = true
    }
  }

  distance(a, b) {
    const rows = Array.from({ length: a.length + 1 }, (_, i) => [i])
    for (let j = 1; j <= b.length; j++) rows[0][j] = j
    for (let i = 1; i <= a.length; i++) {
      for (let j = 1; j <= b.length; j++) {
        rows[i][j] = Math.min(rows[i - 1][j] + 1, rows[i][j - 1] + 1, rows[i - 1][j - 1] + (a[i - 1] === b[j - 1] ? 0 : 1))
      }
    }
    return rows[a.length][b.length]
  }
}
