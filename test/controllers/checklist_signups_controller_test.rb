require "test_helper"
require_relative "../support/signups_world"

# Checklist rules on sign-up positions: setting one up, and the sheet page
# saying why someone can't take a place, with the failing item's fix.
class ChecklistSignupsControllerTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers
  include SignupsWorld

  setup do
    host! "localhost"
    travel_to Time.zone.parse("2026-10-11 12:00")
    @restore_settings = apply_settings(feature_checklists: "true", signups_organizers: "Sheet Organizer > Club")
    build_signups_world
    @sheet = create_world_sheet(created_by: person(:worker), others_relationship_type_ids: [ @parent_of.id ], on_behalf_of_mode: :related_people)
    @position = @sheet.signup_positions.create!(name: "Driver", capacity: 4)
    @checklist = create_checklist("Trip", @club)
    @handbook = add_item(@checklist, :attested, "Handbook", { statement: "Handbook read", attested_by: "person" })
    Checklists::Refresher.new(@checklist.reload, silent: true).call
    @rules_path = signup_sheet_signup_position_signup_position_rules_path(@sheet, @position)
  end

  teardown { @restore_settings&.call }

  def create_checklist(title, team)
    Checklist.create!(title: title, team: team, status: :active, starts_on: Date.new(2026, 9, 1), ends_on: Date.new(2027, 6, 30),
      created_by: person(:admin))
  end

  def add_item(checklist, kind, label, config)
    item = checklist.checklist_items.new(kind: kind.to_s, label: label)
    item.config_params = config
    item.save!
    item
  end

  def attest(name)
    ChecklistAttestation.create!(person: person(name), key: "handbook-read", statement: "Handbook read", attested_at: Time.current, attested_by: person(name))
  end

  def require_checklist(**attributes)
    @position.signup_position_rules.create!(kind: :checklist, checklist: @checklist, **attributes)
  end

  test "an organizer adds a checklist rule from the position's rules" do
    sign_in person(:worker).user

    get edit_signup_sheet_signup_position_path(@sheet, @position)
    assert_select "#new_checklist_rule" do
      assert_select "select[name=?] option[value=?]", "signup_position_rule[checklist_id]", @checklist.id, text: "Trip"
      assert_select "button", text: "Add checklist rule"
    end

    post @rules_path, params: { signup_position_rule: { kind: "checklist", checklist_id: @checklist.id, accept_pending: "1" } }
    assert_redirected_to edit_signup_sheet_signup_position_path(@sheet, @position, anchor: "rules")
    rule = @position.signup_position_rules.sole
    assert_equal [ @checklist, true ], [ rule.checklist, rule.accept_pending ]
    assert_equal "Rule added: Needs Trip: Done or Almost.", flash[:notice]
  end

  test "a checklist the organizer can't see, or an archived one, can't be chosen" do
    hidden = create_checklist("Elsewhere", @other_org)
    archived = create_checklist("Last Year", @club)
    Checklists::Refresher.new(archived, silent: true).call
    archived.update!(status: :archived)
    sign_in person(:worker).user

    get edit_signup_sheet_signup_position_path(@sheet, @position)
    assert_select "option[value=?]", hidden.id, count: 0
    assert_select "option[value=?]", archived.id, count: 0

    [ hidden, archived ].each do |checklist|
      assert_no_difference "SignupPositionRule.count" do
        post @rules_path, params: { signup_position_rule: { kind: "checklist", checklist_id: checklist.id } }
      end
      assert_equal "Pick a checklist you can see.", flash[:alert]
    end

    post @rules_path, params: { signup_position_rule: { kind: "checklist", checklist_id: "" } }
    assert_equal "That rule couldn't be added: Choose a checklist.", flash[:alert]
  end

  test "another organizer can still change a rule on a checklist they can't see" do
    hidden = create_checklist("Elsewhere", @other_org)
    rule = @position.signup_position_rules.create!(kind: :checklist, checklist: hidden)
    sign_in person(:worker).user

    patch signup_sheet_signup_position_signup_position_rule_path(@sheet, @position, rule),
      params: { signup_position_rule: { checklist_id: hidden.id, accept_pending: "1" } }
    assert rule.reload.accept_pending?
  end

  test "with checklists off the rules card offers no checklist rule" do
    with_settings(feature_checklists: "false") do
      sign_in person(:worker).user
      get edit_signup_sheet_signup_position_path(@sheet, @position)
      assert_select "#new_checklist_rule", count: 0
    end
  end

  test "the sheet page says why someone can't take a place, with the failing item's fix" do
    require_checklist
    sign_in person(:student).user

    get signup_sheet_path(@sheet)
    assert_select "##{ActionView::RecordIdentifier.dom_id(slot_for(@position))}", text: /Needs Trip: Done/
    assert_select "#checklist_signup_panel" do
      assert_select "p", text: "Driver needs Trip finished first."
      assert_select "li", text: /Handbook/
      assert_select "form[action=?] button", checklist_checklist_attestations_path(@checklist, item_id: @handbook.id, person_id: person(:student).id),
        text: "I confirm"
    end
  end

  test "a nested checklist's fix links to it" do
    other = create_checklist("Safety", @club)
    add_item(other, :attested, "Waiver", { statement: "Waiver signed", attested_by: "manager" })
    add_item(@checklist, :checklist, "Safety done", { checklist_id: other.id })
    Checklists::Refresher.new(@checklist.reload, silent: true).call
    require_checklist
    sign_in person(:student).user

    get signup_sheet_path(@sheet)
    assert_select "#checklist_signup_panel a[href=?]", checklist_path(other), text: "See Safety"
  end

  test "once the person finishes, the panel goes and they can sign up" do
    require_checklist
    attest(:student)
    Checklists::Refresher.new(@checklist.reload).call
    sign_in person(:student).user

    get signup_sheet_path(@sheet)
    assert_select "#checklist_signup_panel", count: 0
    assert_select "a[href=?]", new_signup_sheet_signup_path(@sheet, slot_id: slot_for(@position).id), text: "Sign up"

    assert_difference "Signup.count", 1 do
      post signup_sheet_signups_path(@sheet), params: { signup: { signup_slot_id: slot_for(@position).id } }
    end
  end

  test "signing up before finishing is refused with the reason" do
    require_checklist
    sign_in person(:student).user

    assert_no_difference "Signup.count" do
      post signup_sheet_signups_path(@sheet), params: { signup: { signup_slot_id: slot_for(@position).id } }
    end
    assert_response :unprocessable_entity
    assert_match "Needs Trip: Done", response.body
  end

  test "someone signing up a relative sees the relative's need, without what they may not see" do
    require_checklist
    attest(:parent)
    sign_in person(:parent).user

    get signup_sheet_path(@sheet)
    assert_select "#checklist_signup_panel" do
      assert_select "p", text: "#{person(:student).display_name} hasn't finished Trip. Ask a leader what's left."
      assert_select "li", text: /Handbook/, count: 0
    end
  end

  test "someone the checklist doesn't cover is told so" do
    @checklist = create_checklist("Crew Trip", @concessions)
    require_checklist
    sign_in person(:student).user

    get signup_sheet_path(@sheet)
    assert_select "#checklist_signup_panel p", text: "You aren't on Crew Trip, so can't take these places."
  end

  test "with checklists off there's no panel, and the rule still holds" do
    require_checklist
    attest(:student)
    Checklists::Refresher.new(@checklist.reload).call

    with_settings(feature_checklists: "false") do
      sign_in person(:student).user
      get signup_sheet_path(@sheet)
      assert_select "#checklist_signup_panel", count: 0
      assert_select "##{ActionView::RecordIdentifier.dom_id(slot_for(@position))}", text: /checklists are turned off/
    end
  end

  test "a checklist a rule needs can't be deleted from its page" do
    require_checklist
    sign_in person(:admin).user

    assert_no_difference "Checklist.count" do
      delete checklist_path(@checklist)
    end
    assert_equal "Sign-up sheet Snack Stand (Driver) needs it; take it off there first", flash[:alert]
  end
end
