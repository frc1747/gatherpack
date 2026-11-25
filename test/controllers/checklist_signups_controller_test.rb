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

  # Closes every checklist's page while closed is set.
  module ClosedChecklists
    mattr_accessor :closed, default: false

    def show?
      !ClosedChecklists.closed && super
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
    assert_equal "Rule added: Must have finished Trip or be partway through.", flash[:notice]
    assert_nil flash[:warning]
  end

  test "the rules card reads the checklist rule as a requirement" do
    sign_in person(:admin).user

    get edit_signup_sheet_signup_position_path(@sheet, @position)
    assert_select "#new_checklist_rule" do
      assert_select "h3", text: "Needs a finished checklist"
      assert_select "label", text: "Checklist they must finish first"
      assert_select ".form-text", text: "Only people who have already finished this checklist can take this position. " \
        "People the checklist leaves out can never take it."
      assert_select "label", text: "Also allow people partway through"
      assert_select ".form-text", text: "Use this when signing up here is how people finish the checklist."
    end
    [ "Finishes a checklist", "In Progress is enough", "For when signing up is how people finish it.",
      "Active checklists whose results you can see for everyone." ].each { |old| assert_no_match old, response.body }

    require_checklist
    get edit_signup_sheet_signup_position_path(@sheet, @position)
    assert_select "#new_checklist_rule", count: 0
    assert_select "p", text: "Now: Must have finished Trip first"
    assert_no_match "Now: Needs Trip", response.body
  end

  test "saving a rule that signing up here counts toward warns, but saves" do
    @sheet.update!(event_type: event_types(:one))
    count = add_item(@checklist, :count, "Outreach events", { base_amount: 1, unit: "events" })
    count.commitment.commitment_sources.create!(kind: "checkins", subject: event_types(:one))
    sign_in person(:admin).user
    warning = "Signing up here counts toward Trip, so requiring it first means only people who already finished can sign up. " \
      "Turn on 'Also allow people partway through' or drop the rule."

    post @rules_path, params: { signup_position_rule: { kind: "checklist", checklist_id: @checklist.id } }
    rule = @position.signup_position_rules.sole
    assert_equal "Rule added: Must have finished Trip first.", flash[:notice]
    assert_equal warning, flash[:warning]
    follow_redirect!
    assert_select ".alert-warning", text: /#{Regexp.escape(warning)}/

    patch signup_sheet_signup_position_signup_position_rule_path(@sheet, @position, rule),
      params: { signup_position_rule: { checklist_id: @checklist.id, accept_pending: "0" } }
    assert_equal warning, flash[:warning]
    follow_redirect!

    patch signup_sheet_signup_position_signup_position_rule_path(@sheet, @position, rule),
      params: { signup_position_rule: { checklist_id: @checklist.id, accept_pending: "1" } }
    assert_equal "Rule saved: Must have finished Trip or be partway through.", flash[:notice]
    assert_nil flash[:warning]
  end

  test "saving a rule nothing here counts toward doesn't warn" do
    @sheet.update!(event_type: event_types(:one))
    count = add_item(@checklist, :count, "Build days", { base_amount: 1, unit: "days" })
    count.commitment.commitment_sources.create!(kind: "checkins", subject: event_types(:two))
    sign_in person(:admin).user

    post @rules_path, params: { signup_position_rule: { kind: "checklist", checklist_id: @checklist.id } }
    assert_equal "Rule added: Must have finished Trip first.", flash[:notice]
    assert_nil flash[:warning]
  end

  test "a rule names the checklist's own words" do
    @checklist.update!(met_word: "Eligible", pending_word: "Pending")
    rule = @position.signup_position_rules.create!(kind: "checklist", checklist: @checklist, accept_pending: true)

    assert_equal "Must have finished Trip or be partway through", rule.description
    assert_equal "Needs Trip: Eligible or Pending", rule.check(person(:student), nil)
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
    assert_select "##{ActionView::RecordIdentifier.dom_id(slot_for(@position))}", text: /Needs Trip: Complete/ do
      assert_select "a[href=?]", checklist_path(@checklist), text: "Trip"
    end
    assert_select "#checklist_signup_panel" do
      assert_select "p", text: "Driver needs Trip finished first."
      assert_select "li", text: /Handbook/
      assert_select "form[action=?] button", checklist_checklist_attestations_path(@checklist, item_id: @handbook.id, person_id: person(:student).id),
        text: "I confirm"
    end
  end

  test "a nested checklist's line carries its item's own fix, confirming on that checklist" do
    other = create_checklist("Safety", @club)
    waiver = add_item(other, :attested, "Waiver", { statement: "Waiver signed", attested_by: "person" })
    add_item(@checklist, :checklist, "Safety done", { checklist_id: other.id })
    Checklists::Refresher.new(other.reload, silent: true).call
    Checklists::Refresher.new(@checklist.reload, silent: true).call
    require_checklist
    sign_in person(:student).user

    get signup_sheet_path(@sheet)
    assert_select "#checklist_signup_panel form[action=?] button", checklist_checklist_attestations_path(other, item_id: waiver.id, person_id: person(:student).id),
      text: "I confirm"
    assert_select "#checklist_signup_panel a[href=?]", checklist_path(other), false, "never the checklist's report"
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
    assert_match "You can't see their results for this place, so can't sign them up here", response.body
    assert_no_match "Needs Trip: Complete", response.body
    assert_no_match "Trip results", response.body
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

  test "a guardian whose ward the checklist doesn't cover is told so, without its name" do
    guardian_of = RelationshipType.create!(parent_label: "Guardian of", child_label: "Ward of", permission: :added_by_admin, guardianship: :minor)
    @people[:guardian] = create_world_person("Guardian")
    relate(:guardian, :student, guardian_of)
    @sheet.update!(others_relationship_type_ids: [ @parent_of.id, guardian_of.id ])
    @checklist = create_checklist("Crew Trip", @concessions)
    require_checklist
    sign_in person(:guardian).user

    get signup_sheet_path(@sheet)
    assert_select "#checklist_signup_panel" do |panel|
      assert_select "p", text: "#{person(:student).display_name}: not open to them"
      assert_no_match "Crew Trip", panel.text
    end
    assert_no_match "isn't on", response.body

    post signup_sheet_signups_path(@sheet), params: { signup: { signup_slot_id: slot_for(@position).id, person_id: person(:student).id } }
    assert_response :unprocessable_entity
    assert_match "Not open to them", response.body
    assert_no_match "Crew Trip", response.body
    assert_no_match "You can't see", response.body
  end

  test "someone who can't see whether a relative is covered gets the fixed reason, without the checklist's name" do
    @checklist = create_checklist("Crew Trip", @concessions)
    require_checklist
    sign_in person(:parent).user

    post signup_sheet_signups_path(@sheet), params: { signup: { signup_slot_id: slot_for(@position).id, person_id: person(:student).id } }
    assert_response :unprocessable_entity
    assert_match "You can't see their results for this place, so can't sign them up here", response.body
    assert_no_match "Crew Trip", response.body
    assert_no_match "Not open", response.body
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

  # Anyone who sees a covered person's result can open the checklist today,
  # so this closes the checklist's page to check the link follows it.
  test "the sheet names a checklist that covers them, unlinked when they can't open it" do
    require_checklist
    sign_in person(:student).user
    ChecklistPolicy.prepend(ClosedChecklists) unless ChecklistPolicy < ClosedChecklists
    ClosedChecklists.closed = true

    get signup_sheet_path(@sheet)
    assert_select "##{ActionView::RecordIdentifier.dom_id(slot_for(@position))}", text: /Needs Trip: Complete/ do
      assert_select "a[href=?]", checklist_path(@checklist), count: 0
    end
  ensure
    ClosedChecklists.closed = false
  end

  test "someone the checklist doesn't cover is told so" do
    @checklist = create_checklist("Crew Trip", @concessions)
    require_checklist
    sign_in person(:student).user

    get signup_sheet_path(@sheet)
    assert_select "##{ActionView::RecordIdentifier.dom_id(slot_for(@position))}", text: /Not open to you/ do |slot|
      assert_no_match "Crew Trip", slot.text
      assert_select "a[href=?]", checklist_path(@checklist), count: 0
    end
    assert_select "#checklist_signup_panel" do |panel|
      assert_select "p", text: "Not open to you"
      assert_no_match "Crew Trip", panel.text
    end
    assert_no_match "aren't on", response.body

    assert_no_difference "Signup.count" do
      post signup_sheet_signups_path(@sheet), params: { signup: { signup_slot_id: slot_for(@position).id } }
    end
    assert_response :unprocessable_entity
    assert_match "Not open to you", response.body
    assert_no_match "Crew Trip", response.body
  end

  test "turned off, a draft or archived, a rule names the checklist to the sheet's organizers, but not to someone it doesn't cover" do
    @checklist = create_checklist("Crew Trip", @concessions)
    require_checklist
    slot_id = ActionView::RecordIdentifier.dom_id(slot_for(@position))
    cases = { "turned off" => -> { }, "draft" => -> { @checklist.update!(status: :draft) }, "archived" => -> { @checklist.update!(status: :archived) } }
    detail = { "turned off" => "checklists are turned off", "draft" => "Crew Trip is a draft", "archived" => "Crew Trip is archived" }

    cases.each do |label, change|
      change.call
      with_settings(feature_checklists: label == "turned off" ? "false" : "true") do
        sign_in person(:student).user
        get signup_sheet_path(@sheet)
        assert_select "##{slot_id}", text: /Not open to you/, message: label
        assert_no_match "Crew Trip", response.body, label
        sign_out :user

        sign_in person(:worker).user
        assert @sheet.organizer?(person(:worker))
        get signup_sheet_path(@sheet)
        assert_select "##{slot_id}", text: /Needs Crew Trip: Complete \(#{detail[label]}\)/, message: label
        sign_out :user
      end
    end
  end

  test "turned off, a draft or archived, someone who can't see a relative's result gets the same fixed reason, covered or not" do
    require_checklist
    crew = @sheet.signup_positions.create!(name: "Crew", capacity: 4)
    crew.signup_position_rules.create!(kind: :checklist, checklist: create_checklist("Crew Trip", @concessions))
    sign_in person(:parent).user
    hidden = "You can't see their results for this place, so can't sign them up here"

    { "turned off" => -> { }, "draft" => -> { Checklist.update_all(status: :draft) }, "archived" => -> { Checklist.update_all(status: :archived) } }.each do |label, change|
      change.call
      with_settings(feature_checklists: label == "turned off" ? "false" : "true") do
        [ @position, crew ].each do |position|
          post signup_sheet_signups_path(@sheet), params: { signup: { signup_slot_id: slot_for(position).id, person_id: person(:student).id } }
          assert_response :unprocessable_entity
          assert_match hidden, response.body, "#{label}: #{position.name}"
          assert_no_match(/Not open|Trip/, response.body, "#{label}: #{position.name}")
        end
      end
    end
  end

  test "the sheet's organizers keep the detailed reason on the sheet page, about someone the checklist doesn't cover" do
    @checklist = create_checklist("Crew Trip", @concessions)
    rule = require_checklist
    assert @sheet.organizer?(person(:admin))

    reason = ->(viewer) { Checklists::SignupViewer.set(person: person(viewer), sheet: true) { rule.reload.check(person(:student), @event) } }
    assert_equal %(Needs <a href="#{checklist_path(@checklist)}">Crew Trip</a>: Complete), reason.call(:admin)
    assert_equal "Not open to you", reason.call(:student)
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

  test "the roster still names a checklist the person isn't on, for an organizer who sees it" do
    @checklist = create_checklist("Crew Trip", @concessions)
    signup = Signup.place!(slot: slot_for(@position), person: person(:student), signed_up_by: person(:student))
    require_checklist
    sign_in person(:admin).user

    get roster_signup_sheet_path(@sheet)
    assert_select "##{ActionView::RecordIdentifier.dom_id(signup)}", text: /Doesn't meet: Needs Crew Trip: Complete/
    assert_no_match "Not open to you", response.body
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
