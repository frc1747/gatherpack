require "test_helper"
require_relative "../support/signups_world"

# Age rules and who sees their outcome. Organizers see pass or fail on
# rules, never a birthday (spec decision 10). An organizer picks the dates
# and the ages, so pass or fail on an age rule would give away the birthday
# of someone they may not see it for: for them the rule isn't checked.
# worker organizes the sheet with a badge and doesn't manage the students;
# club_manager manages Club, so the students, and runs the sheet too.
class SignupAgeRulesTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers
  include SignupsWorld

  setup do
    host! "localhost"
    travel_to Time.zone.parse("2026-10-15 09:00")
    build_signups_world
    @restore_settings = apply_settings(signups_organizers: "Sheet Organizer > Club")
    @club_manager = Person.create!(first_name: "ClubManager", last_name: "World",
      user: User.create!(email: "clubmanager@example.com", password: "Password1!"))
    Membership.create!(person: @club_manager, team: @club, manager: true)
    @sheet = create_world_sheet(created_by: person(:worker))
    @cook = @sheet.signup_positions.create!(name: "Cook", capacity: 5)
    @cook.signup_position_rules.create!(kind: :age, min_age: 16)
    @slot = slot_for(@cook)
  end

  teardown do
    @restore_settings&.call
    travel_back
  end

  test "an organizer can't work out a birthday from age rules by choosing the dates" do
    @sheet = create_world_sheet("Grill", created_by: person(:worker), events: [])
    position = @sheet.signup_positions.create!(name: "Cook", capacity: 5)
    assert_not person(:worker).can_manage(person(:student))
    sign_in person(:worker).user

    post create_dates_signup_sheet_signup_sheet_events_path(@sheet), params: { dates_event_type_id: event_types(:one).id, dates: {
      "0" => { date: "2026-10-24", start_time: "10:00", end_time: "12:00", name: "Day A" },
      "1" => { date: "2026-10-25", start_time: "10:00", end_time: "12:00", name: "Day B" } } }
    post signup_sheet_signup_position_signup_position_rules_path(@sheet, position),
      params: { signup_position_rule: { kind: "age", min_age: "16" } }
    assert_equal 2, @sheet.reload.events.count

    results = @sheet.events.order(:start_time).to_h do |event|
      post signup_sheet_roster_signups_path(@sheet), params: { signup: { signup_slot_id: slot_for(position, event).id, person_id: person(:student).id } }
      get roster_signup_sheet_path(@sheet, event_id: event.id)
      [ event.name, [ response.body.include?("Doesn't meet"), response.body.include?("Age not checked") ] ]
    end

    assert_equal 2, Signup.where(person: person(:student)).count, "placed on both days without a refusal"
    assert_equal results["Day A"], results["Day B"]
    assert_equal [ false, true ], results["Day A"]
  end

  test "an organizer places students with and without a birthday, and the roster says age wasn't checked" do
    sign_in person(:worker).user

    get new_signup_sheet_roster_signup_path(@sheet, signup_slot_id: @slot.id)
    assert_response :success
    %i[ student student2 ].each do |name|
      assert_difference "Signup.count" do
        post signup_sheet_roster_signups_path(@sheet), params: { signup: { signup_slot_id: @slot.id, person_id: person(name).id } }
      end
      assert_redirected_to roster_signup_sheet_path(@sheet)
    end
    assert_not Signup.where(person: [ person(:student), person(:student2) ]).exists?(signed_up_by: nil)

    get roster_signup_sheet_path(@sheet)
    assert_response :success
    [ person(:student), person(:student2) ].each do |student|
      signup = Signup.find_by!(person: student)
      assert_select "##{ActionView::RecordIdentifier.dom_id(signup)}" do
        assert_select "td", text: "Age not checked"
      end
    end
    assert_no_match "Doesn't meet", response.body
    assert_no_match "Must be", response.body
    assert_no_match "birthday", response.body
  end

  test "the age marker reads the same whatever the birthday" do
    over = Person.create!(first_name: "Older", last_name: "World", birthday: Date.new(2000, 1, 1),
      user: User.create!(email: "older@example.com", password: "Password1!"))
    Membership.create!(person: over, team: @students)
    sign_in person(:worker).user

    bodies = [ person(:student), person(:student2), over ].map do |student|
      get new_signup_sheet_roster_signup_path(@sheet, signup_slot_id: @slot.id)
      post signup_sheet_roster_signups_path(@sheet), params: { signup: { signup_slot_id: @slot.id, person_id: student.id } }
      get roster_signup_sheet_path(@sheet)
      css_select("##{ActionView::RecordIdentifier.dom_id(Signup.find_by!(person: student))} td").map(&:text).last(2).first.squish
    end
    assert_equal [ "Age not checked" ] * 3, bodies
  end

  test "an organizer who manages the student sees the age result and needs the override" do
    sign_in @club_manager.user

    assert_no_difference "Signup.count" do
      post signup_sheet_roster_signups_path(@sheet), params: { signup: { signup_slot_id: @slot.id, person_id: person(:student).id } }
    end
    assert_response :unprocessable_entity
    assert_match "Must be 16 or older on Oct 24", response.body

    assert_difference "Signup.count" do
      post signup_sheet_roster_signups_path(@sheet), params: { signup: { signup_slot_id: @slot.id, person_id: person(:student).id, override_rules: "1" } }
    end
    get roster_signup_sheet_path(@sheet)
    assert_select "td", text: "Doesn't meet: Must be 16 or older on Oct 24"
    assert_select "td", text: "Age not checked", count: 0
  end

  test "an admin sees the age result" do
    Signup.place!(slot: @slot, person: person(:student2), signed_up_by: person(:admin), override_rules: true)
    sign_in person(:admin).user

    get roster_signup_sheet_path(@sheet)
    assert_select "td", text: "Doesn't meet: Must be 16 or older (no birthday on file)"
  end

  test "a member who qualifies signs up; one under age is refused and told why" do
    adult = Person.create!(first_name: "Adult", last_name: "World", birthday: Date.new(2000, 1, 1),
      user: User.create!(email: "adult@example.com", password: "Password1!"))
    Membership.create!(person: adult, team: @students)
    sign_in adult.user
    assert_difference "Signup.count" do
      post signup_sheet_signups_path(@sheet), params: { signup: { signup_slot_id: @slot.id } }
    end

    sign_in person(:student).user
    get signup_sheet_path(@sheet)
    assert_match "Must be 16 or older on Oct 24", response.body
    assert_no_difference "Signup.count" do
      post signup_sheet_signups_path(@sheet), params: { signup: { signup_slot_id: @slot.id } }
    end
    assert_response :unprocessable_entity
    assert_match "Must be 16 or older on Oct 24", response.body
  end

  test "signing up someone else under age is refused without the reason" do
    @sheet.update!(others_relationship_type_ids: [ @parent_of.id ])
    sign_in person(:parent).user

    get signup_sheet_path(@sheet)
    assert_no_match "Must be", response.body
    assert_no_difference "Signup.count" do
      post signup_sheet_signups_path(@sheet), params: { signup: { signup_slot_id: @slot.id, person_id: person(:student).id } }
    end
    assert_response :unprocessable_entity
    assert_match SignupPositionRule::AGE_HIDDEN_REASON, response.body
    assert_no_match "Must be", response.body
  end

  test "an organizer signing up their own family is held to age rules without the reason" do
    @sheet.update!(others_relationship_type_ids: [ @sibling_of.id ])
    Relationship.create!(parent: person(:worker), child: person(:student), relationship_type: @sibling_of, created_by: person(:admin))
    sign_in person(:worker).user

    assert_no_difference "Signup.count" do
      post signup_sheet_signups_path(@sheet), params: { signup: { signup_slot_id: @slot.id, person_id: person(:student).id } }
    end
    assert_match SignupPositionRule::AGE_HIDDEN_REASON, response.body
    assert_no_match "Must be", response.body

    assert_no_difference "Signup.count" do
      post signup_sheet_roster_signups_path(@sheet), params: { signup: { signup_slot_id: @slot.id, person_id: person(:student).id, override_rules: "1" } }
    end
    assert_match SignupSheet::SELF_APPROVAL_REASON, response.body
    assert_no_match "Must be", response.body
  end

  test "an organizer can't place family linked by a type members add themselves where there's an age rule" do
    friend_of = RelationshipType.create!(parent_label: "Friend of", child_label: "Friend of", permission: :added_by_participant)
    Relationship.create!(parent: person(:worker), child: person(:student), relationship_type: friend_of, created_by: person(:worker))
    older = Person.create!(first_name: "Older", last_name: "World", birthday: Date.new(2000, 1, 1),
      user: User.create!(email: "older@example.com", password: "Password1!"))
    Membership.create!(person: older, team: @students)
    Relationship.create!(parent: person(:worker), child: older, relationship_type: friend_of, created_by: person(:worker))
    Relationship.create!(parent: person(:worker), child: person(:student2), relationship_type: friend_of, created_by: person(:worker))
    sign_in person(:worker).user

    bodies = [ person(:student), person(:student2), older ].map do |someone|
      [ "", "1" ].map do |override|
        assert_no_difference "Signup.count" do
          post signup_sheet_roster_signups_path(@sheet), params: { signup: { signup_slot_id: @slot.id, person_id: someone.id, override_rules: override } }
        end
        assert_response :unprocessable_entity
        assert_no_match "Must be", response.body
        css_select(".alert").map(&:text).join.squish
      end
    end
    assert_equal 1, bodies.uniq.size, "the same answer whatever the birthday"
    assert_match SignupPositionRule::AGE_FAMILY_REASON, bodies.first.first
    assert_match SignupSheet::SELF_APPROVAL_REASON, bodies.first.last

    sign_in person(:concessions_manager).user
    BadgeAssignment.create!(badge: @organizer_badge, person: person(:concessions_manager))
    @sheet.signup_sheet_organizers.create!(person: person(:concessions_manager))
    assert_difference "Signup.count" do
      post signup_sheet_roster_signups_path(@sheet), params: { signup: { signup_slot_id: @slot.id, person_id: person(:student).id } }
    end
    get roster_signup_sheet_path(@sheet)
    assert_select "td", text: "Age not checked"
  end

  test "an organizer places a stranger without an age check" do
    sign_in person(:worker).user

    assert_difference "Signup.count" do
      post signup_sheet_roster_signups_path(@sheet), params: { signup: { signup_slot_id: @slot.id, person_id: person(:student).id } }
    end
    get roster_signup_sheet_path(@sheet)
    assert_select "td", text: "Age not checked"
    assert_no_match "Doesn't meet", response.body
  end
end
