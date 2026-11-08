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
    assert_equal 11, urls.size
    assert urls.all? { |url| url.start_with?("/assets/") && url.match?(/-[0-9a-f]{8,}\.woff2\z/) }
    get urls.first
    assert_response :success
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
