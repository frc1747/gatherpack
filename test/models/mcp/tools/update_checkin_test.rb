require "test_helper"
require_relative "../../../support/mcp_world"

class Mcp::Tools::UpdateCheckinTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers
  include McpWorld

  setup do
    host! "localhost"
    build_mcp_world
    build_mcp_time_world
    @type = EventType.create!(name: "With fields")
    @open_field = CheckinField.create!(event_type: @type, name: "Open", permission: :added_by_user)
    @admin_field = CheckinField.create!(event_type: @type, name: "Admin only", permission: :added_by_admin)
    @event = create_world_event("With fields", @alpha, Time.utc(2026, 3, 20, 18))
    @event.update!(event_type: @type)
    @checkin = Checkin.create!(person: person(:alpha_member), event: @event)
  end

  def update(viewer, **changes)
    call_tool("update_checkin", user: user(viewer), checkin_id: @checkin.neat_id, **changes)
  end

  def answer(field)
    @checkin.checkin_field_responses.reload.find_by!(checkin_field: field).response
  end

  def assert_unchanged(error)
    before = [ @checkin.reload.notes, answer(@open_field), answer(@admin_field) ]
    assert_refused(error, AuditLog, CheckinFieldResponse) { yield }
    assert_equal before, [ @checkin.reload.notes, answer(@open_field), answer(@admin_field) ]
  end

  test "an admin changes notes and answers and gets the check-in back" do
    result = update(:admin, notes: "Late", field_responses: { @admin_field.neat_id => "A", @open_field.neat_id => "B" })

    assert_equal [ "Late", "A", "B" ], [ @checkin.reload.notes, answer(@admin_field), answer(@open_field) ]
    assert_equal "Late", result.value["notes"]
    assert_equal [ [ @admin_field.neat_id, "Admin only", "A" ], [ @open_field.neat_id, "Open", "B" ] ],
      result.value["field_responses"].map { |item| item.values_at("checkin_field_id", "name", "response") }
    assert_equal @checkin, result.changed
    assert_equal 3, result.changed_records.size
    assert_equal user(:admin).id.to_s, AuditLog.where(item_type: "Checkin", item_id: @checkin.id, event: "update").last.whodunnit
  end

  test "only what's sent changes, and null clears" do
    @checkin.update!(notes: "Keep", created_by: person(:admin))
    update(:admin, field_responses: { @open_field.neat_id => "B", @admin_field.neat_id => "C" })

    assert_nil update(:admin, field_responses: { @open_field.neat_id => nil }).error
    assert_equal [ "Keep", nil, "C" ], [ @checkin.reload.notes, answer(@open_field), answer(@admin_field) ]
    assert_nil update(:admin, notes: nil).value["notes"]
  end

  test "the person checked in changes their notes and open fields" do
    assert_nil update(:alpha_member, notes: "Mine", field_responses: { @open_field.neat_id => "B" }).error
    assert_equal [ "Mine", "B" ], [ @checkin.reload.notes, answer(@open_field) ]
  end

  test "a field they can't answer is refused by name, and nothing else changes" do
    @checkin.refresh_fields

    assert_unchanged("Not allowed: Admin only") do
      update(:alpha_member, notes: "Mine", field_responses: { @open_field.neat_id => "B", @admin_field.neat_id => "A" })
    end
  end

  test "the team's manager can't answer an admin field" do
    assert_equal "Not allowed: Admin only", update(:alpha_manager, field_responses: { @admin_field.neat_id => "A" }).error
    assert_nil answer(@admin_field)
  end

  test "a teammate can't change it, and neither can someone outside the team or a guardian" do
    @checkin.refresh_fields

    assert_unchanged("Not allowed") { update(:ward, notes: "Nope") }
    assert_unchanged("Not found") { update(:beta_member, notes: "Nope") }
    assert_unchanged("Not found") { update(:guardian, notes: "Nope") }
  end

  test "a read token, the setting being off and a bad ID refuse it" do
    @checkin.refresh_fields

    assert_unchanged("Not allowed") { update(:admin, notes: "Nope", scopes: "mcp_read") }
    assert_unchanged("Writes disabled") { update(:admin, notes: "Nope", writes_enabled: false) }
    assert_equal "Not found", call_tool("update_checkin", user: user(:admin), checkin_id: @checkin.id, notes: "Nope").error
  end

  test "a field that isn't on this event's type, or anything else it doesn't take, is refused" do
    @checkin.refresh_fields
    other = CheckinField.create!(event_type: event_types(:two), name: "Elsewhere", permission: :added_by_user)

    assert_unchanged("Not found") { update(:admin, notes: "Nope", field_responses: { other.neat_id => "A" }) }
    assert_unchanged("Not found") { update(:admin, field_responses: { @open_field.id => "A" }) }
    assert_unchanged(/person_id/) { update(:admin, person_id: person(:ward).neat_id) }
    assert_unchanged(/Give notes/) { update(:admin) }
    assert_unchanged(/Give notes/) { update(:admin, field_responses: {}) }
  end

  test "values of the wrong type or with line breaks are refused" do
    @checkin.refresh_fields

    assert_unchanged(/notes/) { update(:admin, notes: 5) }
    assert_unchanged(/notes/) { update(:admin, notes: "a\nb") }
    assert_unchanged(/field_responses/) { update(:admin, field_responses: { @open_field.neat_id => true }) }
    assert_unchanged(/Open/) { update(:admin, field_responses: { @open_field.neat_id => "a\nb" }) }
  end

  test "an event at its limit refuses a change of notes, as the page's edit does, but not an answer, as Arrange" do
    @event.update!(checkin_limit: 1)
    @checkin.refresh_fields

    assert_unchanged(/checkin limit/) { update(:admin, notes: "Nope") }
    assert_nil update(:admin, field_responses: { @open_field.neat_id => "B" }).error

    sign_in user(:admin)
    patch event_checkin_path(@event, @checkin), params: { checkin: { notes: "Nope" } }
    assert_response :unprocessable_entity
    assert_nil @checkin.reload.notes
  end

  test "a refusal at the limit leaves no audit row for the blank answers the model fills in first" do
    @checkin.refresh_fields
    CheckinField.create!(event_type: @type, name: "Added later", permission: :added_by_user)
    @checkin = Checkin.find(@checkin.id)
    @event.update!(checkin_limit: 1)

    assert_refused(/checkin limit/, AuditLog, CheckinFieldResponse) { update(:admin, notes: "Nope") }
  end

  test "changing nothing reports no change" do
    result = with_settings(mcp_write_enabled: "true") { Mcp.tool("update_checkin").run(mcp_context(user(:admin), scopes: "mcp_write"), { checkin_id: @checkin.neat_id, notes: nil }) }

    assert_nil result.error
    assert_nil result.changed
  end

  test "only an answer changed points the log at the answer" do
    result = update(:admin, field_responses: { @open_field.neat_id => "B" })

    assert_equal [ CheckinFieldResponse ], result.changed_records.map(&:class)
    assert_equal result.changed_records.first, result.changed
  end

  test "it runs the check-in's hooks" do
    assert_hook_runs("checkins - update") { update(:admin, notes: "Late") }
  end

  test "a build's show_notes? gates notes, for writing and in the result" do
    with_policy_query(CheckinPolicy, :show_notes?, proc { false }) do
      @checkin.refresh_fields
      @checkin.update!(notes: "Secret", created_by: person(:admin))

      assert_unchanged("Not allowed") { update(:alpha_manager, notes: "Nope") }
      assert_nil update(:alpha_manager, field_responses: { @open_field.neat_id => "B" }).value["notes"]
    end
  end

  test "a build's CheckinFieldResponsePolicy#update? takes over from the page's rule" do
    @checkin.refresh_fields

    with_policy_query(CheckinFieldResponsePolicy, :update?, proc { false }) do
      assert_unchanged("Not allowed: Open") { update(:admin, field_responses: { @open_field.neat_id => "B" }) }
    end
    with_policy_query(CheckinFieldResponsePolicy, :update?, proc { true }) do
      assert_nil update(:alpha_member, field_responses: { @admin_field.neat_id => "A" }).error
    end
  end

  test "a field the viewer can't read is neither written nor returned" do
    @checkin.refresh_fields
    @checkin.checkin_field_responses.find_by!(checkin_field: @admin_field).update!(response: "Hidden value")

    with_policy_query(CheckinField, :readable_by?, proc { |_viewer, _person| name != "Admin only" }) do
      assert_unchanged("Not found") { update(:admin, field_responses: { @admin_field.neat_id => "A" }) }
      assert_unchanged("Not found") { update(:admin, field_responses: { @admin_field.neat_id => "a\nb" }) }

      result = update(:admin, notes: "Fine")
      assert_equal [ "Open" ], result.value["field_responses"].map { |item| item["name"] }
      assert_not_includes result.value.to_json, "Hidden value"
    end
  end

  test "a field linked to a person's value, which may be contact details, is neither written nor returned" do
    @checkin.refresh_fields
    @checkin.checkin_field_responses.find_by!(checkin_field: @admin_field).update!(response: "555-0100")

    # linked? is faked and these fields have no person field behind them, so a build
    # with read levels can't work out who may read them. Whether a linked field is
    # readable isn't what this test is about.
    with_policy_query(CheckinField, :readable_by?, proc { |*| true }) do
      with_policy_query(CheckinField, :linked?, proc { name == "Admin only" }) do
        assert_unchanged("Not allowed: Admin only") { update(:admin, field_responses: { @admin_field.neat_id => "A" }) }

        result = update(:admin, notes: "Fine")
        assert_equal [ "Open" ], result.value["field_responses"].map { |item| item["name"] }
        assert_not_includes result.value.to_json, "555-0100"
      end
    end
  end

  test "notes: it allows and refuses as the page's edit does" do
    [ [ :admin, true ], [ :alpha_manager, true ], [ :alpha_member, true ], [ :ward, false ], [ :beta_member, false ], [ :guardian, false ] ].each do |viewer, allowed|
      sign_in user(viewer)
      patch event_checkin_path(@event, @checkin), params: { checkin: { notes: "From the page" } }
      sign_out user(viewer)
      assert_equal allowed, @checkin.reload.notes == "From the page", "#{viewer} on the page"
      @checkin.update!(notes: nil, created_by: person(:admin))

      update(viewer, notes: "From the tool")
      assert_equal allowed, @checkin.reload.notes == "From the tool", "#{viewer} with the tool"
      @checkin.update!(notes: nil, created_by: person(:admin))
    end
  end

  test "answers: a field the edit form drops is refused, and a member's open one goes through on both" do
    @checkin.refresh_fields
    responses = @checkin.checkin_field_responses.reload.index_by(&:checkin_field_id)
    nested = lambda do |field, value|
      row = responses.fetch(field.id)
      { checkin: { checkin_field_responses_attributes: { "0" => { id: row.id, checkin_field_id: field.id, response: value } } } }
    end

    sign_in user(:alpha_member)
    patch event_checkin_path(@event, @checkin), params: nested.call(@admin_field, "From the page")
    assert_nil answer(@admin_field)
    patch event_checkin_path(@event, @checkin), params: nested.call(@open_field, "From the page")
    assert_equal "From the page", answer(@open_field)
    sign_out user(:alpha_member)

    assert_equal "Not allowed: Admin only", update(:alpha_member, field_responses: { @admin_field.neat_id => "A" }).error
    assert_nil answer(@admin_field)
    assert_nil update(:alpha_member, field_responses: { @open_field.neat_id => "B" }).error
    assert_equal "B", answer(@open_field)
  end

  test "answers: an admin field refuses a manager on Arrange's request, and the same with the tool" do
    @checkin.refresh_fields
    row = @checkin.checkin_field_responses.reload.find_by!(checkin_field: @admin_field)

    sign_in user(:alpha_manager)
    patch "/events/#{@event.id}/field_update", params: { field_id: row.id, response: "From the page" }, as: :json
    assert_response :forbidden
    assert_nil answer(@admin_field)
    sign_out user(:alpha_manager)

    assert_equal "Not allowed: Admin only", update(:alpha_manager, field_responses: { @admin_field.neat_id => "From the tool" }).error
    assert_nil answer(@admin_field)
  end

  test "answers: Arrange's request is refused to those who may not change the check-in, and so is the tool" do
    @checkin.refresh_fields
    row = @checkin.checkin_field_responses.reload.find_by!(checkin_field: @open_field)

    %i[ward beta_member guardian].each do |viewer|
      sign_in user(viewer)
      patch "/events/#{@event.id}/field_update", params: { field_id: row.id, response: "Nope" }, as: :json
      sign_out user(viewer)
      assert_nil answer(@open_field), "#{viewer} on the page"

      assert update(viewer, field_responses: { @open_field.neat_id => "Nope" }).error
      assert_nil answer(@open_field), "#{viewer} with the tool"
    end
  end
end
