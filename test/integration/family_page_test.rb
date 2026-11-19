require "test_helper"
require_relative "../support/checklists_world"

# GET /family. World: parent is the kid's guardian (ChecklistsWorld), and the
# kid is in Members. Flags are set in a throwaway store.
class FamilyPageTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers
  include ChecklistsWorld

  class Plain < Checklists::ItemKind
    def evaluate(person_ids)
      person_ids.index_with { Checklists::Result.not_met("Not yet", fix: { "label" => "Fill out", "path" => "/forms" }) }
    end
  end

  # A shared count, as count items report it.
  class Pooled < Checklists::ItemKind
    def self.settings
      [ Checklists::ItemKind::Setting.new(key: :group_relationship_type_id, type: :text, label: "Through") ]
    end

    def self.default_read_level(_item) = "family"

    def evaluate(person_ids)
      person_ids.index_with { Checklists::Result.not_met("1 of 3 shifts", measures: { "confirmed" => 1, "owed" => 3 }) }
    end
  end

  setup do
    host! "localhost"
    @restore_settings = SettingsTestHelper.apply(feature_my_gatherpack: "true", feature_forms: "true", feature_signups: "true",
      feature_checklists: "true", feature_events: "true")
    Checklists.register_item_kind(:plain, Plain)
    Checklists.register_item_kind(:pooled, Pooled)
    build_checklists_world
    @parent = person(:parent)
    @kid = person(:kid)
    @checklist = create_world_checklist("Trip")
    add_rule(@checklist, :include, :person, person_id: @kid.id)
  end

  teardown do
    Checklists.unregister_item_kind(:plain)
    Checklists.unregister_item_kind(:pooled)
    @restore_settings&.call
  end

  # Access

  test "someone with no wards goes home with no error" do
    sign_in person(:member).user
    get family_path

    assert_redirected_to root_path
    assert_nil flash[:alert]
    assert_nil flash[:notice]
  end

  test "signing in is required" do
    get family_path

    assert_redirected_to new_user_session_path
  end

  test "the page redirects home while the feature is off" do
    sign_in @parent.user
    with_settings(feature_my_gatherpack: "false") { get family_path }

    assert_redirected_to root_path
  end

  test "a guardian with wards gets the page" do
    sign_in @parent.user
    get family_path

    assert_response :success
    assert_select "h1", text: "Your family"
  end

  test "a former guardian sees nothing" do
    Relationship.where(parent: @parent, child: @kid).destroy_all
    sign_in @parent.user
    get family_path

    assert_redirected_to root_path
  end

  test "a non-guardian relative sees nothing" do
    aunt_of = RelationshipType.create!(parent_label: "Aunt of", child_label: "Niece of", permission: :added_by_admin)
    Relationship.create!(parent: person(:member2), child: @kid, relationship_type: aunt_of, created_by: person(:admin))
    sign_in person(:member2).user
    get family_path

    assert_redirected_to root_path
  end

  test "an expired guardianship removes that ward's events and checklists" do
    younger = create_ward("Robin", team: nil, birthday: Date.new(2024, 3, 1))
    event = create_event("Kid Practice", team: @members)
    add_item(@checklist, :plain, "Waiver")
    refresh(@checklist)
    sign_in @parent.user

    with_settings(guardianship_age_limit: "10") do
      get family_path

      assert_select "##{ward_card(younger)}"
      assert_select "##{ward_card(@kid)}", false
      assert_no_match event.name, response.body
      assert_no_match @checklist.title, response.body
    end
  end

  # Menu

  test "a guardian sees Family in the sidebar and as the first phone tab" do
    sign_in @parent.user
    get root_path

    assert_select "[data-menu-group=family] a[href=?]", family_path, text: /Family/
    assert_equal "Family", phone_tab_labels.first
    assert_not_includes phone_tab_labels, "Hours"
  end

  test "someone with no wards doesn't see Family" do
    sign_in person(:member).user
    get root_path

    assert_select "[data-menu-group=family]", false
    assert_select "a[href=?]", family_path, false
    assert_not_includes phone_tab_labels, "Family"
  end

  test "a former guardian doesn't see Family" do
    Relationship.where(parent: @parent, child: @kid).destroy_all
    sign_in @parent.user
    get root_path

    assert_select "a[href=?]", family_path, false
  end

  test "with the flag off, the Family item leaves the sidebar as it was" do
    sign_in @parent.user
    feature = GatherPack::Features.all.find { |candidate| candidate.key == :my_gatherpack }

    with_settings(feature_my_gatherpack: "false") do
      get root_path
      assert_select "a[href=?]", family_path, false
      with_item = css_select(".sidebar").to_html

      # Registering a feature again would replace its Setting, so empty this one.
      items = feature.nav_items
      begin
        feature.instance_variable_set(:@nav_items, [])
        get root_path
        assert_equal css_select(".sidebar").to_html, with_item
      ensure
        feature.instance_variable_set(:@nav_items, items)
      end
    end
  end

  # Cards

  test "one card per ward, in name order, and only their own wards" do
    create_ward("Aaron")
    Relationship.create!(parent: person(:member), child: person(:rookie), relationship_type: @parent_of, created_by: person(:admin))
    sign_in @parent.user
    get family_path

    assert_equal [ "Aaron", "Kid" ], css_select("[data-family-ward] h2").map { |heading| heading.text.strip }
  end

  test "a ward with no first name still reads as theirs" do
    @kid.update_columns(first_name: "", display_name: "Kiddo Tester")
    sign_in @parent.user
    get family_path

    assert_select "[data-family-ward] h2", text: "Kiddo Tester"
  end

  test "says all caught up when nothing needs the guardian" do
    sign_in @parent.user
    get family_path

    assert_select "[data-family-status]", text: "All caught up"
  end

  test "counts what the guardian can act on" do
    create_form("Consent")
    add_item(@checklist, :plain, "Waiver")
    refresh(@checklist)
    sign_in @parent.user
    get family_path

    assert_select "[data-family-status]", text: "2 things need you"
  end

  test "a checklist item with no usable fix doesn't count" do
    item = add_item(@checklist, :plain, "Waiver")
    item.update!(read_level: "family")
    ChecklistResult.where(item: item).update_all(fix: nil)
    refresh(@checklist)
    ChecklistResult.where(item: item).update_all(fix: nil)
    sign_in @parent.user
    get family_path

    assert_select "[data-family-status]", text: "All caught up"
    assert_select "[data-family-row=checklists] .mg-row-detail", text: /Waiver/
  end

  # Forms

  test "forms match the ward's Forms tab, to-do first" do
    done = create_form("Allergies")
    FormResponse.create!(form: done, subject: @kid, status: :complete)
    due = create_form("Consent")
    create_form("Staff Survey", team: @crew)
    sign_in @parent.user

    get family_path
    assert_equal [ "Consent", "Allergies" ], titles("forms")
    assert_select "[data-family-row=forms] a[href=?]", edit_form_response_path(due, @kid), text: "Fill out"

    get person_forms_path(@kid)
    tab = css_select("main").text
    assert_includes tab, "Consent"
    assert_includes tab, "Allergies"
    assert_not_includes tab, "Staff Survey"
  end

  test "forms hide with their feature" do
    create_form("Consent")
    sign_in @parent.user

    with_settings(feature_forms: "false") { get family_path }

    assert_select "[data-family-row=forms]", false
  end

  # Sign-ups

  test "a sign-up shows when the ward takes it, counts for it or made it" do
    open = create_sheet("Snack Stand")
    position = open.signup_positions.create!(name: "Cashier", capacity: 5)
    Signup.create!(signup_slot: position.signup_slots.first, person: @kid, signed_up_by: @kid)
    other = open.signup_positions.create!(name: "Runner", capacity: 5)
    Signup.create!(signup_slot: other.signup_slots.first, person: @parent, on_behalf_of: @kid, signed_up_by: @parent)
    made = open.signup_positions.create!(name: "Setup", capacity: 5)
    Signup.create!(signup_slot: made.signup_slots.first, person: person(:member), signed_up_by: @kid)
    cancelled = open.signup_positions.create!(name: "Cleanup", capacity: 5)
    Signup.create!(signup_slot: cancelled.signup_slots.first, person: @kid, signed_up_by: @kid, status: :cancelled)
    placed = open.signup_positions.create!(name: "Greeter", capacity: 5)
    Signup.create!(signup_slot: placed.signup_slots.first, person: person(:member), signed_up_by: @kid, placed_by_organizer: true)
    sign_in @parent.user

    get family_path

    assert_select "[data-family-row=signups] .mg-row-title a[href=?]", signup_sheet_path(open), count: 3
    assert_select "[data-family-row=signups] .mg-row-title", text: /Cashier/
    assert_select "[data-family-row=signups] .mg-row-title", text: /Runner/
    assert_select "[data-family-row=signups] .mg-row-title", text: /Setup/
    assert_no_match "Cleanup", response.body
    assert_no_match "Greeter", response.body
    assert_no_match person(:member).first_name, css_select("[data-family-row=signups]").text

    get signup_sheet_path(open)
    assert_response :success
  end

  test "a sign-up on a sheet the guardian can't see stays off, as on the sheet page" do
    sheet = create_sheet("Staff Only", team: @crew, relatives: false)
    position = sheet.signup_positions.create!(name: "Lead", capacity: 5)
    Signup.create!(signup_slot: position.signup_slots.first, person: @kid, signed_up_by: @kid)
    sign_in @parent.user

    assert_not SignupSheetPolicy.new(@parent.user, sheet).show?
    get family_path

    assert_select "[data-family-row=signups]", false
    assert_no_match "Staff Only", response.body

    get signup_sheet_path(sheet)
    assert_response :redirect
  end

  test "a past sign-up stays off" do
    past = create_event("Old Game", team: @club, start_time: 2.days.ago)
    sheet = create_sheet("Old Stand", events: [ past ])
    position = sheet.signup_positions.create!(name: "Cashier", capacity: 5)
    Signup.create!(signup_slot: position.signup_slots.first, person: @kid, signed_up_by: @kid)
    sign_in @parent.user

    get family_path

    assert_select "[data-family-row=signups]", false
  end

  # Checklists

  test "a checklist shows through each item's who sees it, like the ward's tab" do
    add_item(@checklist, :plain, "Waiver")
    add_item(@checklist, :plain, "Private Count", read_level: "self_and_leaders")
    refresh(@checklist)
    sign_in @parent.user

    get family_path
    assert_select "[data-family-row=checklists] a[href=?]", person_checklists_path(@kid), text: "Open"
    assert_select "[data-family-row=checklists] .mg-row-detail", text: /Waiver/
    assert_no_match "Private Count", response.body

    get person_checklists_path(@kid)
    assert_match "Waiver", response.body
    assert_no_match "Private Count", response.body
  end

  test "a checklist hidden from guardians stays off the page" do
    secret = create_world_checklist("Coaches Only", read_level: "self_and_leaders")
    add_rule(secret, :include, :person, person_id: @kid.id)
    add_item(secret, :plain, "Hidden Item", read_level: "self_and_leaders")
    refresh(secret)
    sign_in @parent.user
    get family_path

    assert_no_match "Coaches Only", response.body
  end

  test "checklists hide with their feature" do
    add_item(@checklist, :plain, "Waiver")
    refresh(@checklist)
    sign_in @parent.user

    with_settings(feature_checklists: "false") { get family_path }

    assert_select "[data-family-row=checklists]", false
  end

  # Events

  test "a ward's event shows title, time and place, no check-ins and no link" do
    event = create_event("Kid Practice", team: @members, location: "Gym")
    Checkin.create!(event: event, person: person(:member2))
    sign_in @parent.user
    get family_path

    assert_select "[data-family-row=events] .mg-row-title", text: "Kid Practice"
    assert_select "[data-family-row=events] .mg-row-detail", text: /Gym/
    assert_select "[data-family-row=events] a", false
    assert_no_match person(:member2).first_name, response.body
  end

  test "a ward's event links only if the guardian can already reach it" do
    Membership.create!(person: @parent, team: @members)
    event = create_event("Team Night", team: @members)
    sign_in @parent.user
    get family_path

    assert_select "[data-family-row=events] a[href=?]", event_path(event), text: "Team Night"
  end

  test "a ward's team event stays out of the guardian's events list and calendar" do
    event = create_event("Kid Practice", team: @members)
    sign_in @parent.user

    get events_path
    assert_no_match event.name, response.body

    get calendar_calendar_index_path(format: :json, events: "1", start_time: 1.day.ago.iso8601, end_time: 30.days.from_now.iso8601)
    assert_no_match event.name, response.body
  end

  test "events hide with their feature" do
    create_event("Kid Practice", team: @members)
    sign_in @parent.user

    with_settings(feature_events: "false") { get family_path }

    assert_select "[data-family-row=events]", false
  end

  test "ward events are the next five upcoming, soonest first" do
    6.times { |index| create_event("Event #{index}", team: @members, start_time: (index + 1).days.from_now) }
    create_event("Past", team: @members, start_time: 2.days.ago)

    rows = MyGatherpack::WardEvents.new(@kid, viewer_events: Event.none).rows

    assert_equal (0..4).map { |index| "Event #{index}" }, rows.map(&:title)
    assert rows.all? { |row| row.event.nil? }
  end

  # What your family owes

  test "a pooled count shows once for wards pooled together, with open shifts" do
    sibling = create_ward("Robin")
    add_rule(@checklist, :include, :person, person_id: sibling.id)
    add_item(@checklist, :pooled, "Family Shifts", { group_relationship_type_id: @parent_of.id })
    refresh(@checklist)
    sign_in @parent.user
    get family_path

    assert_select "[data-family-owed] .mg-row", count: 1
    assert_select "[data-family-owed] .mg-row-detail", text: /1 of 3.*Kid and Robin/
    assert_select "[data-family-owed] a[href=?]", signup_sheets_path, text: "See open shifts"
  end

  test "a count that isn't pooled isn't under what the family owes" do
    add_item(@checklist, :pooled, "Own Shifts")
    refresh(@checklist)
    sign_in @parent.user
    get family_path

    assert_select "[data-family-owed]", false
  end

  private

  def phone_tab_labels
    css_select(".phone-tabs .phone-tab span").map { |label| label.text.strip }
  end

  def ward_card(ward)
    ActionView::RecordIdentifier.dom_id(ward, :family)
  end

  def titles(row)
    css_select("[data-family-row=#{row}] .mg-row-title").map { |title| title.text.strip }
  end

  def create_ward(name, team: @members, birthday: Date.new(2015, 3, 1))
    ward = create_world_person(name, team, birthday: birthday)
    Relationship.create!(parent: @parent, child: ward, relationship_type: @parent_of, created_by: person(:admin))
    ward
  end

  def create_event(name, team:, start_time: 2.days.from_now, location: nil)
    Event.create!(name: name, start_time: start_time, end_time: start_time + 2.hours, location: location, event_type: event_types(:one), team: team)
  end

  def create_form(title, team: @members)
    form = Form.create!(title: title, team: team, respond_permission: "family", read_permission: "family", status: :draft)
    form.form_audience_rules.create!(effect: :include, target_type: :team, team: team, include_managers: true)
    form.form_audience_rules.reset
    form.update!(status: :open)
    form
  end

  # By default a guardian may sign up their ward, so they see the sheet.
  def create_sheet(title, team: @members, relatives: true, events: [ create_event("Game Day", team: @club) ])
    sheet = SignupSheet.create!(title: title, team: team, status: :open, others_relationship_type_ids: relatives ? [ @parent_of.id ] : [])
    events.each { |event| sheet.signup_sheet_events.create!(event: event) }
    sheet
  end
end
