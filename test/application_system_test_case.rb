require "test_helper"

class ApplicationSystemTestCase < ActionDispatch::SystemTestCase
  # A test's sign_in is used up by the next request the app sees. Only a page
  # visit may use it: a browser's own fetches (manifest, service worker) and a
  # late request from the previous test's page would otherwise take it. The
  # header is absent on origins a browser doesn't trust, so those still count.
  module PageVisitsTakeTheSignIn
    def asset_request?
      super || (env.key?("HTTP_SEC_FETCH_MODE") && env["HTTP_SEC_FETCH_MODE"] != "navigate")
    end
  end
  Warden::Proxy.prepend(PageVisitsTakeTheSignIn)

  if ENV["CAPYBARA_SERVER_PORT"]
    served_by host: "rails-app", port: ENV["CAPYBARA_SERVER_PORT"]

    driven_by :selenium, using: :headless_chrome, screen_size: [ 1400, 1400 ], options: {
      browser: :remote,
      url: "http://#{ENV["SELENIUM_HOST"]}:4444"
    }
  else
    driven_by :selenium, using: :headless_chrome, screen_size: [ 1400, 1400 ]
  end
end
