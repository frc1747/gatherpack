require "application_system_test_case"
require "support/orders_world"

# New request on a phone (spec §3.16): with a pasted link, and with only a
# description and a photo.
class OrderRequestsSystemTest < ApplicationSystemTestCase
  include Devise::Test::IntegrationHelpers
  include OrdersWorld

  # A 1×1 PNG, for the camera input.
  PHOTO = Base64.decode64("iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNk+M9QDwADhgGAWjR9awAAAABJRU5ErkJggg==")

  # config.hosts allows localhost in test, but not Capybara's 127.0.0.1.
  setup do
    @saved_app_host = Capybara.app_host
    @saved_include_port = Capybara.always_include_port
    Capybara.app_host = "http://localhost"
    Capybara.always_include_port = true
    page.driver.browser.manage.window.resize_to(390, 844)
    @world = build_orders_world
  end

  teardown do
    # The browser is shared with other system tests.
    page.driver.browser.manage.window.resize_to(1400, 1400)
    Capybara.app_host = @saved_app_host
    Capybara.always_include_port = @saved_include_port
  end

  # Forgery protection is off in tests by default. With it on, the form's
  # token was made for creating; later saves and Submit must still pass.
  test "with forgery protection on, a new request saves more than once and submits" do
    was = ActionController::Base.allow_forgery_protection
    ActionController::Base.allow_forgery_protection = true
    with_orders(@world) do
      sign_in @world.requester.user
      visit new_orders_request_path

      fill_in "Link", with: "https://www.partsdepot.example/p/AB-123?ref=phone"
      assert_text "Draft saved"
      click_button "Add another item"
      within all("[data-order-line]").last do
        fill_in "Link", with: "https://cornershop.example/item/9"
        assert_text "Other store: cornershop.example"
      end
      # The second save comes after the autosave delay.
      saved_lines = -> { OrderRequest.find_by!(requested_by: @world.requester).order_lines.count }
      deadline = Time.current + Capybara.default_max_wait_time * 2
      sleep 0.1 until saved_lines.call == 2 || Time.current > deadline
      assert_no_text "Not saved yet"
      assert_equal 2, saved_lines.call

      click_button "Submit for approval"
      assert_text "Sent for approval"
      assert OrderRequest.find_by!(requested_by: @world.requester).submitted?
    end
  ensure
    ActionController::Base.allow_forgery_protection = was
  end

  test "Close on a new request with nothing typed makes no draft" do
    with_orders(@world) do
      sign_in @world.requester.user
      visit new_orders_request_path

      click_on "Close"

      assert_current_path orders_requests_path(mine: 1)
      assert_equal 0, OrderRequest.where(requested_by: @world.requester).count
    end
  end

  test "Close right after typing saves what was typed before leaving" do
    with_orders(@world) do
      sign_in @world.requester.user
      visit new_orders_request_path

      fill_in "What is it?", with: "Spare gear"
      # Before the autosave delay runs out.
      click_on "Close"

      assert_current_path orders_requests_path(mine: 1)
      draft = OrderRequest.find_by!(requested_by: @world.requester)
      assert draft.draft?
      assert_equal "Spare gear", draft.order_lines.sole.description
    end
  end

  test "at 390 px a pasted link fills in the store and part number, saves a draft and submits" do
    with_orders(@world) do
      sign_in @world.requester.user
      visit new_orders_request_path

      fill_in "Link", with: "https://www.partsdepot.example/p/AB-123?ref=phone"
      assert_text "From Parts Depot · part AB-123"
      assert_text "Draft saved"
      draft = OrderRequest.find_by!(requested_by: @world.requester)
      assert draft.draft?
      assert_equal "AB-123", draft.order_lines.sole.vendor_part_number

      # A second item from a store nobody listed.
      click_button "Add another item"
      within all("[data-order-line]").last do
        fill_in "Link", with: "https://cornershop.example/item/9"
        assert_text "Other store: cornershop.example"
      end

      assert_no_sideways_scroll
      assert_equal "fixed", evaluate_script("getComputedStyle(document.querySelector('.orders-bar-fixed')).position")
      click_button "Submit for approval"

      assert_text "Sent for approval"
      assert_text "Waiting for approval"
      order_request = OrderRequest.find_by!(requested_by: @world.requester)
      assert_equal draft, order_request
      assert order_request.submitted?
      first, second = order_request.order_lines.to_a
      assert_equal @world.preferred_vendor, first.vendor
      assert_equal "AB-123", first.vendor_part_number
      assert_equal "cornershop.example", second.other_vendor_name
      assert_no_sideways_scroll
    end
  end

  test "at 390 px a description and a camera photo are enough to ask" do
    with_orders(@world) do
      sign_in @world.requester.user
      visit new_orders_request_path

      fill_in "What is it?", with: "Need 2 of these"
      fill_in "How many?", with: "2"
      within("[data-order-line]") { find("summary", text: "More details").click }
      photo = file_fixture_photo
      assert_equal "environment", find_field("Photo")["capture"]
      attach_file "Photo", photo.path
      assert_text "Photo saved"

      assert_no_sideways_scroll
      click_button "Submit for approval"

      assert_text "Waiting for approval"
      line = OrderRequest.find_by!(requested_by: @world.requester).order_lines.sole
      assert_equal "Need 2 of these", line.description
      assert_equal 2, line.quantity
      assert line.not_sure?
      assert line.photo.attached?
      assert_selector "img.orders-line-photo"
    end
  end

  private

  def file_fixture_photo
    file = Tempfile.new([ "broken-part", ".png" ])
    file.binmode
    file.write(PHOTO)
    file.flush
    file
  end

  def assert_no_sideways_scroll
    assert_operator evaluate_script("document.documentElement.scrollWidth"), :<=,
      evaluate_script("document.documentElement.clientWidth")
  end
end
