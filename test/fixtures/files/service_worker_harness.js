// Runs a service worker script (on stdin) against a fake environment and prints
// which requests it handled and what it stored.
const vm = require("vm")
let source = ""
process.stdin.on("data", (chunk) => { source += chunk })
process.stdin.on("end", async () => {
  const listeners = {}
  const stored = []
  const cache = {
    add: async (url) => { stored.push(url) },
    put: async (request) => { stored.push(new URL(request.url).pathname) },
    match: async () => undefined
  }
  const context = {
    URL,
    self: { location: { origin: "https://example.test" }, addEventListener: (name, fn) => { listeners[name] = fn }, clients: { claim: async () => {} } },
    caches: { open: async () => cache, keys: async () => [], delete: async () => true, match: async () => undefined },
    fetch: async () => ({ ok: true, clone: () => ({}) })
  }
  vm.createContext(context)
  vm.runInContext(source, context)

  await new Promise((resolve) => listeners.install({ waitUntil: (p) => p.then(resolve) }))

  const requests = [
    { url: "https://example.test/assets/application-abc123.css", mode: "no-cors", method: "GET" },
    { url: "https://example.test/people", mode: "navigate", method: "GET" },
    { url: "https://example.test/people", mode: "cors", method: "GET", headers: { "Turbo-Frame": "list" } },
    { url: "https://example.test/people.json", mode: "cors", method: "GET" },
    { url: "https://example.test/rails/active_storage/blobs/x/photo.png", mode: "no-cors", method: "GET" },
    { url: "https://example.test/people", mode: "navigate", method: "POST" },
    { url: "https://cdn.example.net/assets/x.js", mode: "no-cors", method: "GET" }
  ]
  const handled = []
  for (const request of requests) {
    let responded
    listeners.fetch({ request, respondWith: (p) => { responded = p } })
    if (responded) {
      handled.push(new URL(request.url).pathname)
      await responded
    }
  }
  console.log(JSON.stringify({ stored: [...new Set(stored)].sort(), handled: [...new Set(handled)].sort() }))
})
