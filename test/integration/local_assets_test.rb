require "test_helper"

class LocalAssetsTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers

  setup { host! "localhost" }

  EXTERNAL_HOSTS = %w[fonts.googleapis.com fonts.gstatic.com cdnjs.cloudflare.com]

  test "login page loads fonts, Popper and Font Awesome from this app" do
    get new_user_session_path
    assert_response :success
    EXTERNAL_HOSTS.each { |host| assert_not_includes response.body, host }
    assert_select "link[rel=stylesheet][href^='/assets/fonts-']"
    assert_select "link[rel=preload][as=font][type='font/woff2'][crossorigin]", 2
    assert_select "script[src^='/assets/fontawesome/all.min-'][data-mutateapproach=sync]"
  end

  test "signed-in pages load Popper from this app" do
    sign_in users(:one)
    get root_path
    assert_response :success
    EXTERNAL_HOSTS.each { |host| assert_not_includes response.body, host }
    assert_select "script[src^='/assets/popper.min-']"
  end

  test "font stylesheet points at digested woff2 files that are served" do
    get stylesheet_path("fonts")
    assert_response :success
    urls = response.body.scan(/url\("([^"]+\.woff2)"\)/).flatten
    assert_equal 69, urls.size
    assert urls.all? { |url| url.start_with?("/assets/") && url.match?(/-[0-9a-f]{8,}\.woff2\z/) }
    get urls.first
    assert_response :success
  end

  test "every font face has a unicode range so pages fetch only the scripts they use" do
    css = Rails.root.join("vendor/assets/stylesheets/fonts.css").read
    assert_equal css.scan("@font-face").size, css.scan("unicode-range: U+").size
    %w[latin latin-ext cyrillic greek vietnamese].each do |subset|
      assert Rails.root.join("vendor/assets/fonts/fira-sans-#{subset}-400.woff2").exist?
    end
  end

  test "assets get a far-future immutable Cache-Control, public files do not" do
    app = ->(env) { [ env["PATH_INFO"] == "/assets/missing.css" ? 404 : 200, {}, [ "" ] ] }
    middleware = GatherPack::ImmutableAssets.new(app)
    call = ->(path) { middleware.call(Rack::MockRequest.env_for(path))[1]["Cache-Control"] }

    assert_equal "public, max-age=#{1.year.to_i}, immutable", call.("/assets/fonts-1a2b3c4d.css")
    assert_nil call.("/robots.txt")
    assert_nil call.("/404.html")
    assert_nil call.("/assets/missing.css")
    assert_nil call.("/assets/fonts.css")
    assert_nil call.("/assets/../robots.txt")
    assert_nil call.("/assets/%2e%2e/robots.txt")
    assert_nil call.("/assets/%2E%2E/robots.txt")
    assert_nil call.("/assets/./fonts-1a2b3c4d.css")
    assert_nil call.("/assets/x/../fonts-1a2b3c4d.css")
  end

  test "the middleware is added first in production only" do
    inserted = []
    stack = Object.new
    stack.define_singleton_method(:insert_before) { |*args| inserted << args }
    initializer = Rails.root.join("config/initializers/local_assets.rb")

    config = Struct.new(:middleware).new(stack)
    Rails.application.define_singleton_method(:config) { config }

    load initializer
    assert_empty inserted

    Rails.env.define_singleton_method(:production?) { true }
    load initializer
    assert_equal [ [ 0, GatherPack::ImmutableAssets ] ], inserted
  ensure
    Rails.application.singleton_class.remove_method(:config)
    Rails.env.singleton_class.remove_method(:production?)
  end

  test "font stylesheet declares each family with swap" do
    css = Rails.root.join("vendor/assets/stylesheets/fonts.css").read
    [ "Fira Sans", "Fira Code", "Bubblegum Sans" ].each do |family|
      assert_includes css, %(font-family: "#{family}")
    end
    assert_equal css.scan("@font-face").size, css.scan("font-display: swap").size
  end

  private

  def stylesheet_path(name)
    ActionController::Base.helpers.stylesheet_path(name)
  end
end
