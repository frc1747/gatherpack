// Runs a service worker script (on stdin) against a fake environment, delivers
// a push, taps the notification, and prints what happened.
const vm = require("vm")
let source = ""
process.stdin.on("data", (chunk) => { source += chunk })
process.stdin.on("end", async () => {
  const windows = JSON.parse(process.argv[2] || "[]")
  const listeners = {}
  const result = {}
  const opened = []
  const makeWindow = (url) => {
    const client = {
      url,
      focus: async () => client,
      navigate: async (target) => { result.navigated = target; return client }
    }
    return client
  }
  const context = {
    URL,
    self: {
      location: { origin: "https://example.test" },
      addEventListener: (name, fn) => { listeners[name] = fn },
      registration: { showNotification: async (title, options) => { result.shown = { title, options } } },
      clients: {
        claim: async () => {},
        matchAll: async () => windows.map(makeWindow),
        openWindow: async (target) => { opened.push(target) }
      }
    },
    caches: { open: async () => ({ add: async () => {} }), keys: async () => [], delete: async () => true, match: async () => undefined },
    fetch: async () => ({ ok: true, clone: () => ({}) })
  }
  vm.createContext(context)
  vm.runInContext(source, context)

  const run = (name, event) => new Promise((resolve) => listeners[name]({ ...event, waitUntil: (p) => p.then(resolve) }))

  await run("push", { data: { json: () => ({ title: "Practice moved", path: "/announcements/1" }) } })

  const tap = (path) => run("notificationclick", { notification: { data: { path }, close: () => { result.closed = true } } })
  await tap("/announcements/1")
  result.opened = opened[0] || null
  const navigated = result.navigated

  opened.length = 0
  await tap("https://elsewhere.test/x")
  result.foreign_opened = opened[0] || result.navigated
  result.navigated = navigated

  console.log(JSON.stringify(result))
})
