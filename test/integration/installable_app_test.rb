require "test_helper"
require "open3"
require "json"

class InstallableAppTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers

  ALLOWED_PATHS = %w[/assets/ /offline.html].freeze

  setup { host! "localhost" }

  # Settings keep their value per process, so swap it there rather than in the
  # shared settings file, and put it back afterwards.
  def with_setting(key, raw)
    setting = Settings.get(key)
    original = setting.instance_variable_get(:@value)
    setting.instance_variable_set(:@value, raw)
    yield
  ensure
    setting.instance_variable_set(:@value, original)
  end

  def with_flag(on, &block)
    with_setting(:feature_installable_app, on.to_s, &block)
  end

  def with_short_name(name, &block)
    with_setting(:pwa_short_name, name, &block)
  end

  def service_worker_script(flag)
    with_flag(flag) { get "/service-worker", headers: { "Accept" => "*/*" } }
    assert_response :success
    response.body
  end

  test "flag defaults to off" do
    assert_equal false, GatherPack::Features.all.find { |f| f.key == :installable_app }.default_enabled
  end

  test "service worker is served without caching" do
    service_worker_script(true)

    assert_equal "no-cache", response.headers["Cache-Control"]
    assert_match %r{javascript}, response.media_type
  end

  test "with the flag on the worker is versioned and caches assets and the offline page" do
    script = service_worker_script(true)

    assert_match(/const VERSION = "[0-9a-f]{12}"/, script)
    assert_includes script, "/offline.html"
    assert_includes script, 'startsWith("/assets/")'
  end

  test "the caching branches match nothing outside the allowlist" do
    script = service_worker_script(true)

    paths = script.scan(%r{["'`](/[^"'`]*)["'`]}).flatten
    assert_equal ALLOWED_PATHS.sort, paths.uniq.sort
    # Everything stored goes through cache.put or cache.add, and only those two.
    assert_equal 1, script.scan("cache.put(").size
    assert_equal 1, script.scan("cache.add(").size
  end

  test "the worker stores only assets and the offline page when run" do
    skip "node is not installed" unless system("node", "--version", out: File::NULL, err: File::NULL)

    script = service_worker_script(true)
    harness = Rails.root.join("test/fixtures/files/service_worker_harness.js")
    out, status = Open3.capture2("node", harness.to_s, stdin_data: script)

    assert status.success?, out
    result = JSON.parse(out)
    assert_equal({ "stored" => [ "/assets/application-abc123.css", "/offline.html" ], "handled" => [ "/assets/application-abc123.css", "/people" ] },
      result.slice("stored", "handled"))
  end

  test "with the flag off the worker deletes its caches and unregisters itself" do
    script = service_worker_script(false)

    assert_includes script, "caches.delete"
    assert_includes script, "unregister()"
    assert_no_match(/addEventListener\("fetch"/, script)
    assert_no_match(/cache\.(put|add)\(/, script)
    assert_no_match(/VERSION/, script)
  end

  test "the offline page is static" do
    get "/offline.html"

    assert_response :success
    assert_includes response.body, "You're offline"
    assert_no_match(/csrf|<script/, response.body)
  end

  test "manifest short name falls back to the site name and stops at 12 characters" do
    with_flag(true) do
      with_short_name("") { get "/manifest.json" }
      manifest = JSON.parse(response.body)
      assert_equal "/", manifest["id"]
      assert_equal Settings[:title].first(12), manifest["short_name"]

      with_short_name("Northwind Community Hub") { get "/manifest.json" }
      assert_equal "Northwind Co", JSON.parse(response.body)["short_name"]

      with_short_name("Kim's Crew") { get "/manifest.json" }
      assert_equal "Kim's Crew", JSON.parse(response.body)["short_name"]
    end
  end

  test "manifest is unchanged with the flag off" do
    with_flag(false) do
      with_short_name("Northwind") { get "/manifest.json" }
    end
    manifest = JSON.parse(response.body)

    assert_equal "", manifest["short_name"]
    assert_nil manifest["id"]
  end

  test "signed-in pages register the worker only with the flag on" do
    sign_in users(:one)

    with_flag(true) { get root_path }
    assert_match(/serviceWorker\.register\("\/service-worker"\)/, response.body)
    assert_match(/Add to Home Screen/, response.body)

    with_flag(false) { get root_path }
    assert_no_match(/serviceWorker/, response.body)
    assert_no_match(/Add to Home Screen/, response.body)
  end
end
