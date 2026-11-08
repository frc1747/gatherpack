require "test_helper"
require "open3"
require "json"

class InstallableAppTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers

  ALLOWED_PATHS = %w[/assets/ /offline.html].freeze

  # Settings are set through Settings against a throwaway store, so the shared
  # settings file is never written and this works whether or not a build caches
  # values on the Setting objects.
  setup do
    host! "localhost"
    @settings_store = Settings.instance.store
    @settings_file = Tempfile.new([ "settings", ".pstore" ])
    Settings.instance.store = PStore.new(@settings_file.path)
    @settings_originals = {}
  end

  teardown do
    @settings_originals.each { |key, value| Settings.get(key).instance_variable_set(:@value, value) }
    Settings.instance.store = @settings_store
    @settings_file.close!
  end

  def with_setting(key, raw)
    setting = Settings.get(key)
    @settings_originals[key] = setting.instance_variable_get(:@value) unless @settings_originals.key?(key)
    previous = setting.instance_variable_get(:@value)
    Settings.set(key, raw)
    yield
  ensure
    Settings.set(key, previous)
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

  def manifest_icons_purposes
    JSON.parse(response.body)["icons"].map { |icon| icon["purpose"] }
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
      with_short_name("Northwind") do
        with_setting(:pwa_description, "Changed") do
          with_setting(:pwa_icon_maskable, "true") { get "/manifest.json" }
        end
      end
    end
    manifest = JSON.parse(response.body)

    assert_equal "", manifest["short_name"]
    assert_nil manifest["id"]
    assert_equal "Get together with GatherPack", manifest["description"]
    assert manifest["icons"].none? { |icon| icon.key?("purpose") }
  end

  test "icons are maskable only when the admin says so" do
    with_flag(true) do
      get "/manifest.json"
      assert manifest_icons_purposes.compact.empty?

      with_setting(:pwa_icon_maskable, "true") { get "/manifest.json" }
      assert_equal [ "any maskable" ], manifest_icons_purposes.uniq
    end
  end

  test "the name and description keep quotes and ampersands" do
    with_flag(true) do
      with_setting(:title, "Kim's Crew & Co") do
        with_setting(:pwa_description, "Tom & Jerry") { get "/manifest.json" }
      end
    end
    manifest = JSON.parse(response.body)

    assert_equal "Kim's Crew & Co", manifest["name"]
    assert_equal "Tom & Jerry", manifest["description"]
  end

  test "the install prompt is only captured when the feature is on" do
    sign_in users(:one)

    with_flag(true) { get root_path }
    assert_includes response.body, "beforeinstallprompt"

    with_flag(false) { get root_path }
    assert_not_includes response.body, "beforeinstallprompt"
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
