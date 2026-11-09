require "test_helper"

class ApplicationSystemTestCase < ActionDispatch::SystemTestCase
  # A browser fetches these by itself, at any moment. Left to count as requests,
  # one can use up the sign_in meant for the test's next page visit.
  Warden.test_mode!
  Warden.asset_paths << %r{\A/(manifest(\.json)?|service-worker(\.js)?)\z}

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
