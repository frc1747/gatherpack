require "test_helper"
require_relative "../support/checklists_count_world"

# A count item's Details on a person's checklists: Upcoming (what they
# are signed up for, not done yet), Done (their confirmed credit records,
# and their group's for a count owed together) and Still open (where they
# can still earn credit), the same through another checklist's line, and
# its Next fix where it can be done.
class ChecklistCountDetailsTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers
  include ChecklistsCountWorld

  # A credit source whose records and places to earn the test sets.
  class TestShiftSource < Commitments::SourceKind
    class << self
      attr_accessor :given_records, :given_links
    end

    def self.label = "Test shifts"
    def self.subject_type = "EventType"
    def self.subject_choices(_commitment, _person) = EventType.all

    def records(person_ids)
      Array(self.class.given_records).select { |record| person_ids.include?(record.person_id) }
    end

    def how_to_earn
      Commitments::HowToEarn.new(text: "Take a shift", links: Array(self.class.given_links))
    end
  end

  setup do
    host! "localhost"
    Commitments.register_source(:test_shifts, TestShiftSource)
    build_commitments_world
    @checklist = create_count_checklist("Concessions", ends_on: Date.new(2099, 12, 31))
    @item = add_count_item(@checklist, "Concessions", { base_amount: 3 })
    @item.commitment.commitment_sources.create!(kind: "test_shifts", subject: @outreach)
    @events = (1..6).map { |day| create_world_event("Game #{day}", Time.zone.local(2099, 1, day, 10)) }
    @draft_sheet = SignupSheet.create!(title: "Hidden", team: @club, status: :draft)
  end

  teardown do
    Commitments.unregister_source(:test_shifts)
    TestShiftSource.given_records = TestShiftSource.given_links = nil
  end

  test "Details keep what is signed up under Upcoming apart from Done, and list up to 5 places still open they may open" do
    TestShiftSource.given_records = [
      record(:member, :confirmed, Date.new(2026, 10, 5), "Stocking: Game 0", @events.first),
      record(:member, :planned, Date.new(2026, 11, 20), "Stocking: Game 9", @draft_sheet),
      record(:member2, :confirmed, Date.new(2026, 10, 6), "Someone else's shift", @events.first)
    ]
    TestShiftSource.given_links = [ [ "Hidden sheet", signup_sheet_path(@draft_sheet) ] ] + @events.map { |event| [ event.name, event ] } +
      [ [ "Game 1", signup_sheet_path(@draft_sheet) ] ]

    with_checklists do
      refresh_all
      sign_in person(:member).user
      get person_checklists_path(person(:member))
      assert_response :success

      assert_select "details", 1
      assert_equal %w[Upcoming Done], css_select("details div.fw-semibold").map { |div| div.text.strip }.first(2)
      assert_equal [ "Nov 20 · Stocking: Game 9" ], css_select("details [data-count-detail=upcoming] li").map { |li| li.text.squish }
      assert_equal [ "Oct 5 · Stocking: Game 0" ], css_select("details [data-count-detail=done] li").map { |li| li.text.squish },
        "signed up isn't done"
      assert_no_match "signed up", response.body
      assert_select "details a", text: "Stocking: Game 0"
      assert_select "details a", text: "Stocking: Game 9", count: 0, message: "a draft sheet the member can't open isn't linked"
      assert_no_match "Someone else", response.body

      assert_select "details div.fw-semibold", text: "Still open"
      assert_equal @events.first(5).map { |event| event_path(event) }, css_select("details li a").map { |a| a["href"] }.last(5)
      assert_select "details a", text: "Hidden sheet", count: 0
      assert_select "details a", text: "Game 6", count: 0, message: "at most 5"
    end
  end

  test "Still open leaves out the events the person already holds a place at" do
    held = [ @events.first, @events.second ]
    TestShiftSource.given_records = held.map do |event|
      record(:member, :planned, event.start_time.to_date, "Stocking: #{event.name}", event, dedupe_key: Commitments.event_key(event.id, person(:member).id))
    end
    TestShiftSource.given_links = [ [ "Game 1", @events.first ],
      [ "Game 2", "#{signup_sheet_path(@draft_sheet)}##{ActionView::RecordIdentifier.dom_id(@events.second)}" ], [ "Game 3", @events.third ] ]

    upcoming, _, chances = Checklists::Kinds::Count.person_detail(@item, person(:member))
    assert_equal 2, upcoming.size
    assert_equal [ "Game 3" ], chances.map(&:first)
  end

  test "another checklist's line passing the count through shows the same lists, and the count has no card of its own" do
    TestShiftSource.given_records = [ record(:member, :planned, Date.new(2026, 11, 20), "Stocking: Game 9", @events.first) ]
    TestShiftSource.given_links = [ [ "Game 2", @events.second ] ]
    travel = create_count_checklist("Travel", ends_on: Date.new(2099, 12, 31))
    line = travel.checklist_items.new(kind: "checklist", label: "Concessions")
    line.config_params = { checklist_id: @checklist.id }
    line.save!

    with_checklists do
      refresh_all
      Checklists::Refresher.new(travel.reload, silent: true).call
      sign_in person(:member).user
      get person_checklists_path(person(:member))
      assert_response :success

      assert_select "##{ActionView::RecordIdentifier.dom_id(@checklist)}", false
      assert_select "##{ActionView::RecordIdentifier.dom_id(travel)} details [data-count-detail=upcoming] li", text: "Nov 20 · Stocking: Game 9"
      assert_select "##{ActionView::RecordIdentifier.dom_id(travel)} details p", text: "Nothing yet"
      assert_select "##{ActionView::RecordIdentifier.dom_id(travel)} details a[href=?]", event_path(@events.second), text: "Game 2"
    end
  end

  test "a count owed together lists the group's records under Done, naming who earned them, to people who see the group" do
    pooled = add_count_item(@checklist, "Family shifts", { base_amount: 3, group_relationship_type_id: @parent_of.id })
    pooled.commitment.commitment_sources.create!(kind: "test_shifts", subject: @outreach)
    TestShiftSource.given_records = [
      record(:organizer, :confirmed, Date.new(2026, 10, 7), "Parent's shift", @events.first),
      record(:kid, :confirmed, Date.new(2026, 10, 5), "Kid's shift", @events.second)
    ]

    with_checklists do
      refresh_all
      sign_in person(:kid).user
      get person_checklists_path(person(:kid))
      assert_response :success

      done = css_select("details [data-count-detail=done]").map { |list| list.css("li").map { |li| li.text.squish } }
      assert_includes done, [ "Oct 7 · Parent's shift · by #{person(:organizer).identifier_name}", "Oct 5 · Kid's shift" ]
    end

    _, done, = Checklists::Kinds::Count.person_detail(pooled, person(:kid), viewer: person(:organizer))
    assert_equal [ "Parent's shift", "Kid's shift" ], done.map(&:label), "the parent in the group sees it too"
    _, done, = Checklists::Kinds::Count.person_detail(pooled, person(:kid), viewer: person(:member))
    assert_equal [ "Kid's shift" ], done.map(&:label), "a teammate outside the group sees only the person's own"
    _, done, = Checklists::Kinds::Count.person_detail(pooled, person(:kid))
    assert_equal [ "Kid's shift" ], done.map(&:label)
  end

  test "the Next fix for a sign-up opens the sheet where it can be taken" do
    sheet = SignupSheet.create!(title: "Concessions", team: @club, status: :open)
    at_sheet = signup_sheet_path(sheet, anchor: ActionView::RecordIdentifier.dom_id(@events.first))
    TestShiftSource.given_links = [ [ "Game 1, Fri Jan 1", at_sheet ] ]
    with_checklists do
      assert_equal({ "label" => "Next: Game 1, Fri Jan 1", "path" => at_sheet, "by" => "person" }, count_result(@checklist, :member, @item).fix)

      TestShiftSource.given_links = [ [ "Concessions", sheet ] ]
      assert_equal signup_sheet_path(sheet), count_result(@checklist, :member, @item).fix["path"]
    end
  end

  private

  def record(name, state, date, label, link, dedupe_key: nil)
    Commitments::CreditRecord.new(person_id: person(name).id, quantity: 1, state: state, date: date, label: label, link: link, dedupe_key: dedupe_key)
  end

  def refresh_all
    Checklists::Refresher.new(@checklist.reload, silent: true).call
  end
end
