require "test_helper"
require_relative "../support/signups_world"

# Positions, rules, dates, slots, organizers and audience: the setup
# sections of a sheet's edit page.
class SignupSheetSetupControllersTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers
  include SignupsWorld

  setup do
    host! "localhost"
    build_signups_world
    @restore_settings = apply_settings(signups_organizers: "Sheet Organizer > Club")
    @sheet = create_world_sheet(created_by: person(:worker))
    @position = @sheet.signup_positions.create!(name: "Cashier", capacity: 2)
  end

  teardown do
    @restore_settings&.call
  end

  test "the setup page shows every section to an organizer" do
    sign_in person(:worker).user

    get edit_signup_sheet_path(@sheet)
    assert_response :success
    %w[ positions dates slots organizers audience ].each { |section| assert_select "##{section}" }
    assert_select "#positions", text: /Cashier/
    assert_select "a[href=?]", roster_signup_sheet_path(@sheet)
  end

  test "an organizer adds, edits, reorders and removes positions" do
    sign_in person(:worker).user

    get new_signup_sheet_signup_position_path(@sheet)
    assert_response :success
    assert_difference "SignupPosition.count" do
      post signup_sheet_signup_positions_path(@sheet), params: { signup_position: {
        name: "Main dish", kind: "items", unit: "pizzas", capacity: "6", question: "What kind?", question_required: "1" } }
    end
    dish = @sheet.signup_positions.find_by!(name: "Main dish")
    assert_redirected_to edit_signup_sheet_signup_position_path(@sheet, dish)
    assert dish.items?
    assert_equal [ 6, "pizzas", true ], [ dish.capacity, dish.unit, dish.question_required ]
    assert slot_for(dish), "a slot is made on the sheet's date"

    get edit_signup_sheet_signup_position_path(@sheet, dish)
    assert_response :success
    patch signup_sheet_signup_position_path(@sheet, dish), params: { signup_position: { capacity: "" } }
    assert_nil dish.reload.capacity

    patch signup_sheet_signup_position_path(@sheet, dish), params: { move: "up" }
    assert_equal [ dish, @position ], @sheet.signup_positions.reload.to_a

    assert_difference "SignupPosition.count", -1 do
      delete signup_sheet_signup_position_path(@sheet, dish)
    end
  end

  test "a position's kind can change only while nobody is signed up" do
    sign_in person(:worker).user

    patch signup_sheet_signup_position_path(@sheet, @position), params: { signup_position: { kind: "items", unit: "cases" } }
    assert @position.reload.items?
    patch signup_sheet_signup_position_path(@sheet, @position), params: { signup_position: { kind: "people" } }
    assert @position.reload.people?

    Signup.place!(slot: slot_for(@position), person: person(:student), signed_up_by: person(:student))
    get edit_signup_sheet_signup_position_path(@sheet, @position)
    assert_select "input[name=?][disabled]", "signup_position[kind]", count: 2
    assert_select ".form-text", text: "Can't change while people are signed up."

    patch signup_sheet_signup_position_path(@sheet, @position), params: { signup_position: { kind: "items", name: "Till" } }
    assert_response :unprocessable_entity
    assert_select ".invalid-feedback, .error", text: /can't change while people are signed up/
    @position.reload
    assert @position.people?
    assert_equal "Cashier", @position.name
  end

  test "a position with sign-ups can't be removed" do
    Signup.place!(slot: slot_for(@position), person: person(:student), signed_up_by: person(:student))
    sign_in person(:worker).user

    assert_no_difference "SignupPosition.count" do
      delete signup_sheet_signup_position_path(@sheet, @position)
    end
    assert_match "has sign-ups", flash[:alert]
  end

  test "an organizer adds and removes rules of each kind" do
    sign_in person(:worker).user
    rules_path = signup_sheet_signup_position_signup_position_rules_path(@sheet, @position)

    post rules_path, params: { signup_position_rule: { kind: "badge", badge_ids: [ "", @license_badge.id ] } }
    post rules_path, params: { signup_position_rule: { kind: "age", min_age: "18", max_age: "" } }
    post rules_path, params: { signup_position_rule: { kind: "team", team_ids: [ "", @concessions.id, @students.id ] } }
    assert_equal [ "Needs the Alcohol License badge", "Age 18 or older", "In Concessions or Students" ], @position.signup_position_rules.reload.map(&:description)

    get edit_signup_sheet_path(@sheet)
    assert_select "#positions li", text: /Needs the Alcohol License badge/

    rule = @position.signup_position_rules.first
    assert_difference "SignupPositionRule.count", -1 do
      delete signup_sheet_signup_position_signup_position_rule_path(@sheet, @position, rule)
    end
  end

  test "an organizer edits a rule in place" do
    sign_in person(:worker).user
    rule = @position.signup_position_rules.create!(kind: :team, team_ids: [ @concessions.id ])

    get edit_signup_sheet_signup_position_path(@sheet, @position)
    assert_select "##{ActionView::RecordIdentifier.dom_id(rule)}" do
      assert_select "input[type=checkbox][name=?][value=?][checked]", "signup_position_rule[team_ids][]", @concessions.id
      assert_select "button", text: "Save team rule"
      assert_select "button", text: "Remove"
    end
    assert_select "button", text: "Add age rule"

    patch signup_sheet_signup_position_signup_position_rule_path(@sheet, @position, rule),
      params: { signup_position_rule: { team_ids: [ "", @students.id, @club.id ] } }
    assert_redirected_to edit_signup_sheet_signup_position_path(@sheet, @position, anchor: "rules")
    assert_equal [ @club.id, @students.id ].sort, rule.reload.team_ids.sort
    assert_equal "Rule saved: In Club or Students.", flash[:notice]
  end

  test "a position takes one rule of each kind" do
    sign_in person(:worker).user
    @position.signup_position_rules.create!(kind: :team, team_ids: [ @concessions.id ])

    assert_no_difference "SignupPositionRule.count" do
      post signup_sheet_signup_position_signup_position_rules_path(@sheet, @position), params: { signup_position_rule: { kind: "team", team_ids: [ @students.id ] } }
    end
    assert_redirected_to edit_signup_sheet_signup_position_path(@sheet, @position, anchor: "rules")
    assert_equal "That rule couldn't be added: This position already has a team rule; change it instead.", flash[:alert]
  end

  test "a team rule must be the sheet's team or below it" do
    sign_in person(:worker).user

    assert_no_difference "SignupPositionRule.count" do
      post signup_sheet_signup_position_signup_position_rules_path(@sheet, @position), params: { signup_position_rule: { kind: "team", team_ids: [ @students.id, @other_org.id ] } }
    end
    assert_match "Pick Club or teams below it", flash[:alert]

    rule = @position.signup_position_rules.create!(kind: :team, team_ids: [ @students.id ])
    patch signup_sheet_signup_position_signup_position_rule_path(@sheet, @position, rule), params: { signup_position_rule: { team_ids: [ @students.id, @other_org.id ] } }
    assert_match "Pick Club or teams below it", flash[:alert]
    assert_equal [ @students.id ], rule.reload.team_ids
  end

  test "an organizer attaches upcoming events and detaches one" do
    practice = create_world_event("Practice", 1.week.from_now, team: @concessions)
    elsewhere = create_world_event("Elsewhere", 1.week.from_now, team: @other_org)
    past = create_world_event("Last Year", 1.year.ago)
    sign_in person(:worker).user

    get new_signup_sheet_signup_sheet_event_path(@sheet)
    assert_response :success
    assert_select "label", text: /Practice/
    assert_select "label", text: /Elsewhere|Last Year|Game Day/, count: 0

    [ elsewhere, past ].each do |event|
      assert_no_difference "SignupSheetEvent.count" do
        post signup_sheet_signup_sheet_events_path(@sheet), params: { event_ids: [ practice.id, event.id ] }
      end
      assert_match "Nothing was added", flash[:alert]
    end

    assert_difference "SignupSheetEvent.count" do
      post signup_sheet_signup_sheet_events_path(@sheet), params: { event_ids: [ practice.id ] }
    end
    assert_redirected_to edit_signup_sheet_path(@sheet, anchor: "dates")
    assert slot_for(@position, practice)

    sheet_event = @sheet.signup_sheet_events.find_by!(event: practice)
    assert_difference "SignupSheetEvent.count", -1 do
      delete signup_sheet_signup_sheet_event_path(@sheet, sheet_event)
    end
  end

  test "the add dates page filters by event type" do
    practice = create_world_event("Practice", 1.week.from_now, team: @concessions)
    social = create_world_event("Social", 1.week.from_now, team: @concessions)
    event_types(:two).update!(name: "Socials")
    social.update!(event_type: event_types(:two))
    sign_in person(:worker).user

    get new_signup_sheet_signup_sheet_event_path(@sheet)
    assert_select "select#event_type_id option", text: "Socials"
    assert_select "label", text: /Practice/
    assert_select "label", text: /Social/

    get new_signup_sheet_signup_sheet_event_path(@sheet, event_type_id: event_types(:two).id)
    assert_response :success
    assert_select "label", text: /Social/
    assert_select "label", text: /Practice/, count: 0
  end

  test "a badge organizer can only attach events they can already see" do
    # worker is in Concessions, not Students, so can't see Students' events.
    hidden = create_world_event("Students Meeting", 1.week.from_now, team: @students)
    visible = create_world_event("Club Night", 1.week.from_now, team: @club)
    sign_in person(:worker).user

    get new_signup_sheet_signup_sheet_event_path(@sheet)
    assert_select "label", text: /Club Night/
    assert_select "label", text: /Students Meeting/, count: 0

    assert_no_difference "SignupSheetEvent.count" do
      post signup_sheet_signup_sheet_events_path(@sheet), params: { event_ids: [ hidden.id ] }
    end
    assert_redirected_to new_signup_sheet_signup_sheet_event_path(@sheet)
    assert_equal "Only events listed here can be added. Nothing was added.", flash[:alert]
    assert_not @sheet.events.include?(hidden)

    sign_in person(:admin).user
    get new_signup_sheet_signup_sheet_event_path(@sheet)
    assert_select "label", text: /Students Meeting/
    assert_difference "SignupSheetEvent.count", 2 do
      post signup_sheet_signup_sheet_events_path(@sheet), params: { event_ids: [ hidden.id, visible.id ] }
    end
  end

  test "detaching a date with sign-ups is refused" do
    Signup.place!(slot: slot_for(@position), person: person(:student), signed_up_by: person(:student))
    sign_in person(:worker).user

    assert_no_difference "SignupSheetEvent.count" do
      delete signup_sheet_signup_sheet_event_path(@sheet, @sheet.signup_sheet_events.first)
    end
    assert_equal "Game Day has sign-ups, so it can't be removed from the sheet", flash[:alert]
  end

  test "the grid sets caps and turns slots off in one save" do
    second = @sheet.signup_positions.create!(name: "Runner")
    cashier = slot_for(@position)
    runner = slot_for(second)
    sign_in person(:worker).user

    get signup_sheet_signup_slots_path(@sheet)
    assert_response :success
    assert_select "input[name=?]", "slots[#{cashier.id}][capacity]"

    patch update_all_signup_sheet_signup_slots_path(@sheet), params: { slots: {
      cashier.id => { capacity: "5", on: "1" },
      runner.id => { capacity: "", on: "0" } } }
    assert_redirected_to signup_sheet_signup_slots_path(@sheet)
    assert_equal [ 5, false ], [ cashier.reload.capacity, cashier.disabled ]
    assert_equal [ nil, true ], [ runner.reload.capacity, runner.disabled ]

    patch update_all_signup_sheet_signup_slots_path(@sheet), params: { slots: { cashier.id => { capacity: "0", on: "1" }, runner.id => { capacity: "", on: "1" } } }
    assert_match "Nothing was saved", flash[:alert]
    assert_equal 5, cashier.reload.capacity
    assert runner.reload.disabled, "an invalid cell rolls back the whole grid"

    patch signup_sheet_signup_slot_path(@sheet, runner), params: { signup_slot: { capacity: "3", on: "1" } }
    assert_equal [ 3, false ], [ runner.reload.capacity, runner.disabled ]
  end

  test "an organizer adds a grant holder as organizer, and removes them, but not the last" do
    BadgeAssignment.create!(badge: @organizer_badge, person: person(:concessions_manager))
    sign_in person(:worker).user

    get edit_signup_sheet_path(@sheet)
    assert_select "#organizers select option", text: person(:concessions_manager).display_name
    assert_select "#organizers select option", text: person(:student).display_name, count: 0

    assert_difference "SignupSheetOrganizer.count" do
      post signup_sheet_signup_sheet_organizers_path(@sheet), params: { signup_sheet_organizer: { person_id: person(:concessions_manager).id } }
    end
    added = @sheet.signup_sheet_organizers.find_by!(person: person(:concessions_manager))
    assert_difference "SignupSheetOrganizer.count", -1 do
      delete signup_sheet_signup_sheet_organizer_path(@sheet, added)
    end

    assert_no_difference "SignupSheetOrganizer.count" do
      delete signup_sheet_signup_sheet_organizer_path(@sheet, @sheet.signup_sheet_organizers.first)
    end
    assert_match "at least one organizer", flash[:alert]
  end

  test "a grant holder can't add someone without an organizer badge" do
    sign_in person(:worker).user

    assert_no_difference "SignupSheetOrganizer.count" do
      post signup_sheet_signup_sheet_organizers_path(@sheet), params: { signup_sheet_organizer: { person_id: person(:student).id } }
    end
    assert_match "must hold an organizer badge", flash[:alert]
  end

  test "an organizer adds and removes audience rules" do
    sign_in person(:worker).user

    assert_difference "SignupAudienceRule.count", 3 do
      post signup_sheet_signup_audience_rules_path(@sheet), params: { signup_audience_rule: { effect: "include", target_type: "team", team_id: @students.id, include_managers: "0" } }
      post signup_sheet_signup_audience_rules_path(@sheet), params: { signup_audience_rule: { effect: "include", target_type: "badge", badge_id: @license_badge.id } }
      post signup_sheet_signup_audience_rules_path(@sheet), params: { signup_audience_rule: { effect: "exclude", target_type: "person", person_id: person(:student2).id } }
    end
    assert @sheet.open_to?(person(:student))
    assert @sheet.open_to?(person(:worker))
    assert_not @sheet.open_to?(person(:student2))
    assert_not @sheet.open_to?(person(:concessions_manager))

    get edit_signup_sheet_path(@sheet)
    assert_select "#audience li", text: /Include Students \(members only, not managers\)/

    assert_difference "SignupAudienceRule.count", -1 do
      delete signup_sheet_signup_audience_rule_path(@sheet, @sheet.signup_audience_rules.first)
    end
  end

  test "an audience team must be the sheet's team or below it" do
    sign_in person(:worker).user

    assert_no_difference "SignupAudienceRule.count" do
      post signup_sheet_signup_audience_rules_path(@sheet), params: { signup_audience_rule: { effect: "include", target_type: "team", team_id: @other_org.id } }
    end
  end

  test "a member who isn't an organizer is denied every setup action" do
    sign_in person(:student).user
    rule = @position.signup_position_rules.create!(kind: :age, min_age: 18)
    audience_rule = @sheet.signup_audience_rules.create!(effect: :include, target_type: :team, team: @students)
    sheet_event = @sheet.signup_sheet_events.first
    organizer = @sheet.signup_sheet_organizers.first
    slot = slot_for(@position)
    practice = create_world_event("Practice", 1.week.from_now)

    [ new_signup_sheet_signup_position_path(@sheet), edit_signup_sheet_signup_position_path(@sheet, @position),
      new_signup_sheet_signup_sheet_event_path(@sheet), signup_sheet_signup_slots_path(@sheet) ].each do |path|
      get path
      assert_redirected_to root_path, "GET #{path}"
    end

    assert_no_difference %w[ SignupPosition.count SignupPositionRule.count SignupSheetEvent.count SignupSheetOrganizer.count SignupAudienceRule.count ] do
      post signup_sheet_signup_positions_path(@sheet), params: { signup_position: { name: "Mine" } }
      patch signup_sheet_signup_position_path(@sheet, @position), params: { signup_position: { name: "Mine" } }
      patch signup_sheet_signup_position_path(@sheet, @position), params: { move: "down" }
      delete signup_sheet_signup_position_path(@sheet, @position)
      post signup_sheet_signup_position_signup_position_rules_path(@sheet, @position), params: { signup_position_rule: { kind: "age", min_age: "1" } }
      delete signup_sheet_signup_position_signup_position_rule_path(@sheet, @position, rule)
      post signup_sheet_signup_sheet_events_path(@sheet), params: { event_ids: [ practice.id ] }
      delete signup_sheet_signup_sheet_event_path(@sheet, sheet_event)
      patch update_all_signup_sheet_signup_slots_path(@sheet), params: { slots: { slot.id => { capacity: "9", on: "0" } } }
      patch signup_sheet_signup_slot_path(@sheet, slot), params: { signup_slot: { capacity: "9" } }
      post signup_sheet_signup_sheet_organizers_path(@sheet), params: { signup_sheet_organizer: { person_id: person(:student).id } }
      delete signup_sheet_signup_sheet_organizer_path(@sheet, organizer)
      post signup_sheet_signup_audience_rules_path(@sheet), params: { signup_audience_rule: { effect: "exclude", target_type: "person", person_id: person(:student2).id } }
      delete signup_sheet_signup_audience_rule_path(@sheet, audience_rule)
    end
    assert_equal "Cashier", @position.reload.name
    assert_equal [ nil, false ], [ slot.reload.capacity, slot.disabled ]
  end

  test "changes are audited with who made them" do
    sign_in person(:worker).user

    post signup_sheet_signup_positions_path(@sheet), params: { signup_position: { name: "Runner" } }
    version = AuditLog.where(item_type: "SignupPosition").order(:created_at).last
    assert_equal "create", version.event
    assert_equal person(:worker).user.id.to_s, version.whodunnit
  end
end
