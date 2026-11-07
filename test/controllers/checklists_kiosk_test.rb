require "test_helper"
require_relative "../support/checklists_world"

# The checklist items an organizer chose to list on the time kiosk
# (show_on_kiosk), shown as a scan panel under the scanned person's card.
class ChecklistsKioskTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers
  include ChecklistsWorld

  setup do
    host! "localhost"
    TimeKioskController::TEST_STORE.clear
    build_checklists_world
    @checklist = create_world_checklist
    add_rule(@checklist, :include, :team, team_id: @members.id)
    @agreement = add_item(@checklist, :attested, "Team agreement", { statement: "Agreement signed", attested_by: "person" })
    @token = Token.create!(tokenable: person(:member), value: "scan-#{SecureRandom.hex(4)}")
    refresh(@checklist)
    sign_in person(:admin).user
  end

  test "the time kiosk lists items chosen for it that aren't done, for the person who scanned" do
    @agreement.update!(show_on_kiosk: true)

    scan

    assert_response :success
    assert_select "#kiosk-still-need li", count: 1, text: "Team agreement"
  end

  test "the time kiosk lists nothing for items not chosen for it" do
    scan

    assert_response :success
    assert_select "#kiosk-still-need", count: 0
  end

  test "the time kiosk lists nothing for a manager the checklist covers" do
    @agreement.update!(show_on_kiosk: true)
    manager = person(:crew_manager)
    add_rule(@checklist, :include, :person, person_id: manager.id)
    refresh(@checklist)
    token = Token.create!(tokenable: manager, value: "scan-#{SecureRandom.hex(4)}")
    assert ChecklistResult.exists?(checklist: @checklist, person: manager, item_id: nil)

    scan token

    assert_response :success
    assert_select "#kiosk-still-need", count: 0
  end

  test "the time kiosk evaluates only checklists with an item chosen for it" do
    @agreement.update!(show_on_kiosk: true)
    other = create_world_checklist("Other")
    add_rule(other, :include, :team, team_id: @members.id)
    add_item(other, :attested, "Other agreement", { statement: "Other signed", attested_by: "person" })
    refresh(other)
    evaluated = []
    original = Checklists.method(:status_for)
    Checklists.define_singleton_method(:status_for) do |checklist, *args, **kwargs|
      evaluated << checklist.title
      original.call(checklist, *args, **kwargs)
    end
    begin
      scan
    ensure
      Checklists.define_singleton_method(:status_for, original)
    end

    assert_response :success
    assert_equal [ "Trip" ], evaluated.uniq
  end

  test "the time kiosk lists nothing while checklists are off" do
    @agreement.update!(show_on_kiosk: true)

    scan with_checklists: false

    assert_response :success
    assert_select "#kiosk-still-need", count: 0
  end

  test "the scan reads no checklist results when no item is chosen for the kiosk" do
    tables = []
    callback = ->(*, payload) { tables << payload[:sql][/FROM "(checklist\w*)"/, 1] }
    ActiveSupport::Notifications.subscribed(callback, "sql.active_record") { scan }

    assert_response :success
    assert_equal [ "checklist_items" ], tables.compact.uniq
  end

  test "an organizer chooses whether an item shows at the kiosk" do
    sign_in person(:club_manager).user
    with_feature do
      get edit_checklist_checklist_item_path(@checklist, @agreement)
      assert_select "input[name='checklist_item[show_on_kiosk]']"

      patch checklist_checklist_item_path(@checklist, @agreement), params: { confirmed: "1", checklist_item: { label: "Team agreement",
        show_on_kiosk: "1", config: { statement: "Agreement signed", attested_by: "person" } } }
    end

    assert @agreement.reload.show_on_kiosk?
  end

  private

  def scan(token = @token, with_checklists: true)
    block = -> { get time_kiosk_path, params: { time_kiosk: { tool: "find_token", token_value: token.value } } }
    with_checklists ? with_feature(&block) : block.call
  end
end
