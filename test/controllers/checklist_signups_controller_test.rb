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

  # Met for everyone, but its kind hides every result from every viewer,
  # runners included (kind caps apply to whoever looks).
  class HiddenFromViewers < Checklists::ItemKind
    def self.visible_person_ids(_item, _viewer, _person_ids) = []

    def evaluate(person_ids)
      person_ids.index_with { Checklists::Result.met("Fine") }
    end
  end

  def create_checklist(title, team, status: :active)
    Checklist.create!(title: title, team: team, status: status, starts_on: Date.new(2026, 9, 1), ends_on: Date.new(2099, 12, 31),
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

  def grant_to_sheet_organizers
    ChecklistGrant.create!(checklist: @checklist, badge: @organizer_badge, item_ids: [], access: :status, created_by: person(:admin))
  end

  test "a grant holder adds a checklist rule from the position's rules" do
    grant_to_sheet_organizers
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
    assert_equal "Rule added: Needs Trip: Complete or In Progress.", flash[:notice]
  end

  test "a rule names the checklist's own words" do
    @checklist.update!(met_word: "Eligible", pending_word: "Pending")
    rule = @position.signup_position_rules.create!(kind: "checklist", checklist: @checklist, accept_pending: true)

    assert_equal "Needs Trip: Eligible or Pending", rule.description
  end

  test "someone who runs the checklist can choose it" do
    sign_in person(:admin).user

    get edit_signup_sheet_signup_position_path(@sheet, @position)
    assert_select "option[value=?]", @checklist.id, text: "Trip"
  end

  test "an organizer covered by a checklist, who doesn't run it, can't choose it" do
    sign_in person(:worker).user
    assert ChecklistResult.exists?(checklist: @checklist, item_id: nil, person: person(:worker)), "the worker has a row of their own"

    get edit_signup_sheet_signup_position_path(@sheet, @position)
    assert_select "option[value=?]", @checklist.id, count: 0

    assert_no_difference "SignupPositionRule.count" do
      post @rules_path, params: { signup_position_rule: { kind: "checklist", checklist_id: @checklist.id } }
    end
    assert_equal "Pick an active checklist whose results you can see for everyone.", flash[:alert]
  end

  test "an overall an item's kind hides can't be chosen, by a grant holder or by someone who runs it" do
    grant_to_sheet_organizers
    Checklists.register_item_kind(:hidden_from_grants, HiddenFromViewers)
    add_item(@checklist, :hidden_from_grants, "Private", {})

    [ :worker, :admin ].each do |name|
      sign_in person(name).user
      get edit_signup_sheet_signup_position_path(@sheet, @position)
      assert_select "option[value=?]", @checklist.id, count: 0

      assert_no_difference "SignupPositionRule.count" do
        post @rules_path, params: { signup_position_rule: { kind: "checklist", checklist_id: @checklist.id } }
      end
      assert_equal "Pick an active checklist whose results you can see for everyone.", flash[:alert]
      sign_out :user
    end
  ensure
    Checklists.unregister_item_kind(:hidden_from_grants)
  end

  test "a draft, an archived checklist, or one they can't see, can't be chosen" do
    hidden = create_checklist("Elsewhere", @other_org)
    draft = create_checklist("Next Year", @club, status: :draft)
    archived = create_checklist("Last Year", @club)
    Checklists::Refresher.new(archived, silent: true).call
    archived.update!(status: :archived)
    sign_in person(:admin).user

    get edit_signup_sheet_signup_position_path(@sheet, @position)
    assert_select "option[value=?]", hidden.id, count: 1, message: "an admin sees every active checklist"
    assert_select "option[value=?]", draft.id, count: 0
    assert_select "option[value=?]", archived.id, count: 0

    [ draft, archived ].each do |checklist|
      assert_no_difference "SignupPositionRule.count" do
        post @rules_path, params: { signup_position_rule: { kind: "checklist", checklist_id: checklist.id } }
      end
      assert_equal "Pick an active checklist whose results you can see for everyone.", flash[:alert]
    end

    sign_out :user
    grant_to_sheet_organizers
    sign_in person(:worker).user
    assert_no_difference "SignupPositionRule.count" do
      post @rules_path, params: { signup_position_rule: { kind: "checklist", checklist_id: hidden.id } }
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
    assert_select "##{ActionView::RecordIdentifier.dom_id(slot_for(@position))}", text: /Needs Trip: Complete/
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
    assert_match "Needs Trip: Complete", response.body
  end

  test "someone who can sign a relative up but can't see their result learns nothing until refused, and then only the fixed reason" do
    require_checklist
    sign_in person(:parent).user

    get signup_sheet_path(@sheet)
    assert_select "#checklist_signup_panel", count: 0
    assert_no_match "Needs Trip", response.body
    assert_select "a[href=?]", new_signup_sheet_signup_path(@sheet, slot_id: slot_for(@position).id), text: "Sign up"

    assert_no_difference "Signup.count" do
      post signup_sheet_signups_path(@sheet), params: { signup: { signup_slot_id: slot_for(@position).id, person_id: person(:student).id } }
    end
    assert_response :unprocessable_entity
    assert_match "You can't see their Trip results, so can't sign them up here", response.body
    assert_no_match "Needs Trip: Complete", response.body
    assert_no_match "Handbook", response.body
  end

  test "someone who can't see a relative's result can still sign them up once they pass" do
    require_checklist
    attest(:student)
    Checklists::Refresher.new(@checklist.reload).call
    sign_in person(:parent).user

    get signup_sheet_path(@sheet)
    assert_select "#checklist_signup_panel", count: 0
    assert_select "a[href=?]", new_signup_sheet_signup_path(@sheet, slot_id: slot_for(@position).id), text: "Sign up"

    assert_difference "Signup.count", 1 do
      post signup_sheet_signups_path(@sheet), params: { signup: { signup_slot_id: slot_for(@position).id, person_id: person(:student).id } }
    end
    assert_redirected_to signup_sheet_path(@sheet)
  end

  test "a guardian whose ward the checklist doesn't cover is told so, with the real reason" do
    guardian_of = RelationshipType.create!(parent_label: "Guardian of", child_label: "Ward of", permission: :added_by_admin, guardianship: :minor)
    @people[:guardian] = create_world_person("Guardian")
    relate(:guardian, :student, guardian_of)
    @sheet.update!(others_relationship_type_ids: [ @parent_of.id, guardian_of.id ])
    @checklist = create_checklist("Crew Trip", @concessions)
    require_checklist
    sign_in person(:guardian).user

    get signup_sheet_path(@sheet)
    assert_select "#checklist_signup_panel p", text: "#{person(:student).display_name} isn't on Crew Trip, so can't take these places."

    post signup_sheet_signups_path(@sheet), params: { signup: { signup_slot_id: slot_for(@position).id, person_id: person(:student).id } }
    assert_response :unprocessable_entity
    assert_match "Needs Crew Trip: Complete", response.body
    assert_no_match "You can't see", response.body
  end

  test "someone who can't see whether a relative is covered gets the fixed reason" do
    @checklist = create_checklist("Crew Trip", @concessions)
    require_checklist
    sign_in person(:parent).user

    post signup_sheet_signups_path(@sheet), params: { signup: { signup_slot_id: slot_for(@position).id, person_id: person(:student).id } }
    assert_response :unprocessable_entity
    assert_match "You can't see their Crew Trip results, so can't sign them up here", response.body
    assert_no_match "Needs Crew Trip", response.body
  end

  test "a guardian who can sign their ward up sees the ward's need, with its items" do
    guardian_of = RelationshipType.create!(parent_label: "Guardian of", child_label: "Ward of", permission: :added_by_admin, guardianship: :minor)
    @people[:guardian] = create_world_person("Guardian")
    relate(:guardian, :student, guardian_of)
    @sheet.update!(others_relationship_type_ids: [ @parent_of.id, guardian_of.id ])
    require_checklist
    sign_in person(:guardian).user

    get signup_sheet_path(@sheet)
    assert_select "##{ActionView::RecordIdentifier.dom_id(slot_for(@position))}", text: /Needs Trip: Complete/
    assert_select "#checklist_signup_panel" do
      assert_select "h3", text: person(:student).display_name
      assert_select "li", text: /Handbook/
    end

    post signup_sheet_signups_path(@sheet), params: { signup: { signup_slot_id: slot_for(@position).id, person_id: person(:student).id } }
    assert_response :unprocessable_entity
    assert_match "Needs Trip: Complete", response.body
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

  test "a rule on a checklist set back to draft, or archived, shows no panel and a fixed reason" do
    require_checklist
    sign_in person(:student).user

    { draft: "is a draft", archived: "is archived" }.each do |status, words|
      @checklist.update!(status: status)
      get signup_sheet_path(@sheet)
      assert_select "#checklist_signup_panel", count: 0
      assert_select "##{ActionView::RecordIdentifier.dom_id(slot_for(@position))}", text: /Needs Trip: Complete \(Trip #{words}\)/
    end
  end

  test "one organizer adds the rule; another, who can't see the results, learns nothing on the roster and places only people who pass" do
    signup = Signup.place!(slot: slot_for(@position), person: person(:student), signed_up_by: person(:student))
    sign_in person(:admin).user
    post @rules_path, params: { signup_position_rule: { kind: "checklist", checklist_id: @checklist.id } }
    assert @position.signup_position_rules.exists?(kind: :checklist)

    get roster_signup_sheet_path(@sheet)
    assert_select "##{ActionView::RecordIdentifier.dom_id(signup)}", text: /Doesn't meet: Needs Trip: Complete/, message: "the admin sees it"
    sign_out :user

    hidden = "You can't see their Trip results, so can't sign them up here"
    sign_in person(:worker).user
    get roster_signup_sheet_path(@sheet)
    assert_response :success
    assert_no_match "Needs Trip", response.body
    assert_no_match "Doesn't meet", response.body
    assert_no_match hidden, response.body

    # Someone who fails is refused with the fixed reason, override or not.
    [ nil, "1" ].each do |override|
      assert_no_difference "Signup.count", "override #{override.inspect}" do
        post signup_sheet_roster_signups_path(@sheet),
          params: { signup: { signup_slot_id: slot_for(@position).id, person_id: person(:concessions_manager).id, override_rules: override }.compact }
      end
      assert_response :unprocessable_entity
      assert_match hidden, response.body
      assert_no_match "Needs Trip: Complete", response.body
    end

    # Someone who passes is placed, though the organizer can't see why.
    attest(:student2)
    Checklists::Refresher.new(@checklist.reload).call
    assert_difference "Signup.count", 1 do
      post signup_sheet_roster_signups_path(@sheet), params: { signup: { signup_slot_id: slot_for(@position).id, person_id: person(:student2).id } }
    end
    assert_redirected_to roster_signup_sheet_path(@sheet)

    helper = slot_for(@sheet.signup_positions.create!(name: "Helper", capacity: 4))
    moving = Signup.place!(slot: helper, person: person(:concessions_manager), signed_up_by: person(:concessions_manager))
    [ nil, "1" ].each do |override|
      patch move_signup_sheet_roster_signup_path(@sheet, moving),
        params: { signup: { signup_slot_id: slot_for(@position).id, override_rules: override }.compact }
      assert_response :unprocessable_entity
      assert_match hidden, response.body
      assert_no_match "Needs Trip: Complete", response.body
      assert_equal helper, moving.reload.signup_slot
    end
  end

  test "an organizer who sees the results places as before" do
    grant_to_sheet_organizers
    require_checklist
    attest(:student2)
    Checklists::Refresher.new(@checklist.reload).call
    sign_in person(:worker).user

    post signup_sheet_roster_signups_path(@sheet), params: { signup: { signup_slot_id: slot_for(@position).id, person_id: person(:student).id } }
    assert_response :unprocessable_entity
    assert_match "Needs Trip: Complete", response.body

    assert_difference "Signup.count", 1 do
      post signup_sheet_roster_signups_path(@sheet), params: { signup: { signup_slot_id: slot_for(@position).id, person_id: person(:student2).id } }
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
