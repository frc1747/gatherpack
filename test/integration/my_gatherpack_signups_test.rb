require "test_helper"
require "my_gatherpack_test_helper"
require_relative "../support/signups_world"

class MyGatherpackSignupsTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers
  include MyGatherpackTestHelper
  include SignupsWorld

  # Stands in for Person#wards, which another branch defines. Prepended once;
  # it does nothing unless a test sets +wards+.
  module WardsStandIn
    mattr_accessor :wards

    def wards
      WardsStandIn.wards || (defined?(super) ? super : Person.none)
    end
  end
  Person.prepend(WardsStandIn) unless Person.include?(WardsStandIn)

  setup do
    host! "localhost"
    travel_to Time.zone.parse("2026-10-20 09:00")
    turn_on_my_gatherpack
    # SignupsWorld set this in a store turn_on_my_gatherpack replaced.
    Settings[:feature_signups] = "true"
    build_signups_world
    @sheet = create_world_sheet
    @cashier = @sheet.signup_positions.create!(name: "Cashier", capacity: 5)
  end

  # Sets a setting in the current store for a block, then puts it back.
  def with_flag(key, value)
    previous = Settings[key]
    Settings[key] = value
    yield
  ensure
    Settings[key] = previous.to_s
  end

  teardown do
    WardsStandIn.wards = nil
    restore_my_gatherpack
  end

  test "shows the viewer's own sign-up under Coming up" do
    create_world_signup(@cashier, :worker)
    sign_in person(:worker).user

    get root_path

    assert_select "[data-home-column=coming_up] .mg-row-title a[href=?]", signup_sheet_path(@sheet), text: "Cashier"
    assert_select ".mg-row-detail", text: /10:00 AM · Snack Stand/
    assert_select ".mg-row-ward", false
    assert_select ".badge", text: "Signed up"
  end

  test "hides with the sign-ups flag, with the home flag, and with nothing to show" do
    create_world_signup(@cashier, :worker)
    sign_in person(:worker).user

    get root_path
    assert_select "[data-home-column=coming_up] .mg-row-title a", text: "Cashier"

    with_flag(:feature_signups, "false") do
      get root_path
      assert_no_match "Cashier", response.body
    end

    with_flag(:feature_my_gatherpack, "false") do
      get root_path
      assert_select ".mg-home", false
      assert_select ".signups-summary"
    end

    sign_in person(:student2).user
    get root_path
    assert_no_match "Cashier", response.body
    assert_select "[data-home-column=coming_up] .mg-row-title a", text: "Cashier", count: 0
  end

  test "a ward's row names the ward and others' rows name the person" do
    create_world_signup(@cashier, :student, signed_up_by: person(:parent))
    create_world_signup(@cashier, :student2, signed_up_by: person(:parent))
    Membership.create!(person: person(:parent), team: @club)
    WardsStandIn.wards = [ person(:student) ]
    sign_in person(:parent).user

    get root_path

    assert_select ".mg-row-ward", count: 1, text: "for Student"
    assert_select ".mg-row-detail", text: /StudentTwo World/
    assert_select ".mg-row-detail", text: /Student World/, count: 0
    assert_no_match(/guardian/i, css_select(".mg-row-detail, .mg-row-ward").text)
  end

  test "a ward covering for another ward: the row names that ward and the one working" do
    create_world_signup(@cashier, :student, signed_up_by: person(:parent), on_behalf_of: person(:student2))
    Membership.create!(person: person(:parent), team: @club)
    WardsStandIn.wards = [ person(:student), person(:student2) ]
    sign_in person(:parent).user

    get root_path

    assert_select ".mg-row-ward", count: 1, text: "for StudentTwo"
    assert_select ".mg-row-detail", text: /Student World · .*on behalf of StudentTwo World/
  end

  test "a place that counts for the viewer isn't labelled as a ward's" do
    create_world_signup(@cashier, :student, on_behalf_of: person(:parent))
    Membership.create!(person: person(:parent), team: @club)
    WardsStandIn.wards = [ person(:student) ]
    sign_in person(:parent).user

    get root_path

    assert_select ".mg-row-title a", text: "Cashier"
    assert_select ".mg-row-ward", false
    assert_select ".mg-row-detail", text: /Taken for you by Student World/
  end

  test "a place the viewer made for a ward on the viewer's behalf names the ward, not the viewer" do
    create_world_signup(@cashier, :student, signed_up_by: person(:parent), on_behalf_of: person(:parent))
    Membership.create!(person: person(:parent), team: @club)
    WardsStandIn.wards = [ person(:student) ]
    sign_in person(:parent).user

    get root_path

    assert_select ".mg-row-ward", false
    assert_select ".mg-row-detail", text: /Student World · On your behalf/
  end

  test "rows match the dashboard card for the same person" do
    create_world_signup(@cashier, :worker)
    other = @sheet.signup_positions.create!(name: "Pizza runner", capacity: 2)
    Signup.create!(signup_slot: slot_for(other), person: person(:worker), signed_up_by: person(:parent), on_behalf_of: person(:student))
    closed = create_world_sheet("Closed Stand", status: :draft)
    hidden = closed.signup_positions.create!(name: "Hidden", capacity: 1)
    create_world_signup(hidden, :worker)
    sign_in person(:worker).user

    get root_path
    home = css_select("[data-home-column=coming_up] .mg-row").map { |row| row.text.squish }.select { |row| row.include?("Snack Stand") }

    Settings[:feature_my_gatherpack] = "false"
    get root_path
    card = css_select(".signups-summary li").map { |entry| entry.text.squish }
    summary = SignupsSummary.new(person(:worker).user)

    assert_equal summary.signups.size, home.size
    assert_equal card.size, home.size
    summary.signups.each do |signup|
      assert(home.one? { |row| row.include?(signup.signup_position.name) && row.include?(signup.signup_sheet.title) }, "#{signup.signup_position.name} missing from home")
      assert(card.one? { |entry| entry.include?(signup.signup_position.name) }, "#{signup.signup_position.name} missing from the card")
    end
    assert_empty home.grep(/Hidden/)
    assert_empty card.grep(/Hidden/)
    assert(home.any? { |row| row.include?("Taken for you") || row.include?("on behalf of Student World") })
  end

  test "an organizer gets Manage with Sign-ups; a member does not" do
    Settings[:signups_organizers] = "Sheet Organizer > Club"

    assert MyGatherpack::Menu.new(person(:worker).user).manage.any? { |item| item.path == :signup_sheets_path }
    assert_empty MyGatherpack::Menu.new(person(:student).user).manage
    with_flag(:feature_signups, "false") do
      assert_empty MyGatherpack::Menu.new(person(:worker).user).manage
    end
  end
end
