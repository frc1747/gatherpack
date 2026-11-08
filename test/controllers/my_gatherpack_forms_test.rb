require "test_helper"
require_relative "../support/forms_world"
require_relative "../support/settings_test_helper"

# The forms to-dos on the My GatherPack home page.
class MyGatherpackFormsTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers
  include FormsWorld
  include SettingsTestHelper

  setup do
    host! "localhost"
    build_person_fields_world
    @restore_settings = SettingsTestHelper.apply(feature_my_gatherpack: "true", feature_forms: "true")
    @sections = MyGatherpack.sections.dup
    @checks = MyGatherpack::Menu.manager_checks.dup
  end

  teardown do
    MyGatherpack.sections.replace(@sections)
    MyGatherpack::Menu.manager_checks.replace(@checks)
    @restore_settings.call
  end

  test "a member's form shows as a to-do, counted in the heading and linked as the Forms page links it" do
    form = create_world_form("Meal Choices", closes_at: 3.days.from_now)
    sign_in person(:a1).user

    get root_path

    assert_select "h1", text: /You have 1 thing to do/
    assert_select ".mg-row", text: /Meal Choices/ do
      assert_select "a.btn", text: "Fill out"
      assert_select "a[href=?]", edit_form_response_path(form, person(:a1))
      assert_select ".mg-row-ward", false
      assert_select "*", text: /guardian/i, count: 0
    end
  end

  test "a row for a ward names the ward, with guardian wording, and matches the Forms page" do
    create_world_form("Meal Choices", closes_at: 3.days.from_now)
    sign_in person(:parent_a1).user

    get forms_path
    page_entries = css_select("a.list-group-item").map { |link| [ link.text.squish, link["href"] ] }
    get root_path

    assert_select ".mg-row-ward", text: "for A1"
    assert_select ".mg-row-detail", text: /You're their guardian/
    href = css_select(".mg-row a.btn").first["href"]
    assert_includes page_entries.map(&:last), href
    assert_includes page_entries.map(&:first).join, "for A1"
  end

  test "to-dos sort past nearest due date first, then undated" do
    create_world_form("Later", closes_at: 5.days.from_now)
    create_world_form("Undated")
    create_world_form("Sooner", closes_at: 1.day.from_now)
    sign_in person(:a1).user

    get root_path

    assert_equal %w[ Sooner Later Undated ], css_select(".mg-row-title").map { |title| title.text.squish }
    assert_select "h1", text: /3 things to do/
  end

  test "a finished form and one only a guardian fills in are left out, and so is one outside the audience" do
    done = create_world_form("Finished")
    add_choice(done, "Meal", %w[ Beef Veg ])
    respond(done, :a1, as: :a1, answers: {})
    create_world_form("Parents Only", respond: "guardians")
    create_world_form("Open To A1")

    sign_in person(:a1).user
    get root_path
    assert_equal [ "Open To A1" ], css_select(".mg-row-title").map { |title| title.text.squish }
    assert_select "h1", text: /1 thing to do/

    sign_in person(:outsider).user
    get root_path
    assert_select ".mg-row", count: 0
    assert_select "h1", text: /all caught up/
  end

  test "a row waiting only on the viewer's signature says Sign" do
    form = create_world_form("Consent Form", closes_at: 2.days.from_now)
    add_signature(form, signer: "guardian")
    respond(form, :a1, as: :a1, answers: {})
    sign_in person(:parent_a1).user

    get root_path

    assert_select ".mg-row", text: /Consent Form/ do
      assert_select "a.btn", text: "Sign"
      assert_select "a.btn", text: "Fill out", count: 0
      assert_select "a[href=?]", form_response_path(form, person(:a1))
    end
  end

  test "a leader's waiting forms show with Open and the Forms page's link" do
    form = create_world_form("Paper Consent", leader_todo: true)
    add_signature(form, signer: "leader")
    respond(form, :a1, as: :a1, answers: {})
    sign_in person(:den_a_leader).user

    get root_path

    assert_select ".mg-row", text: /Paper Consent/ do
      assert_select "a.btn", text: "Open"
      assert_select "a[href=?]", form_path(form, status: "waiting")
      assert_select ".mg-row-ward", false
    end
  end

  test "the section hides with the forms flag and with nothing to show" do
    create_world_form("Meal Choices")
    sign_in person(:a1).user

    with_settings(feature_forms: "false") do
      get root_path
      assert_select ".mg-row", text: /Meal Choices/, count: 0
    end

    sign_in person(:outsider).user
    get root_path
    assert_select "h1", text: /all caught up/
    assert_select "[data-home-column=todo]", count: 0
  end

  test "a Forms creator gets Manage without managing a team; others don't" do
    badge = create_world_badge("Form Creator")
    BadgeAssignment.create!(badge: badge, person: person(:a1))

    with_settings(forms_creator_badge: "Form Creator") do
      assert MyGatherpack::Menu.new(person(:a1).user).manages_anything?
      assert_not MyGatherpack::Menu.new(person(:a2).user).manages_anything?
      assert_equal [ "Forms" ], MyGatherpack::Menu.new(person(:a1).user).manage.map(&:label)
    end
    assert_not MyGatherpack::Menu.new(person(:a1).user).manages_anything?
  end
end
