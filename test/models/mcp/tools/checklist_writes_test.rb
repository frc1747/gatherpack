require "test_helper"
require_relative "../../../support/mcp_checklists_world"

# Each write tool allows what the checklist screen it mirrors allows: for every viewer, the
# screen's request and the tool change records, or not, together.
class Mcp::Tools::ChecklistWritesTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers
  include McpChecklistsWorld

  VIEWERS = %i[alpha_member kid_parent crew_lead grant_holder organizer alpha_manager admin beta_member].freeze

  setup do
    host! "localhost"
    build_mcp_world
    build_mcp_checklists_world
    @commitment = @shifts.commitment
  end

  # Whether the tool changes model's rows for viewer, undone after, and the result.
  def tool_changes?(model, viewer, name, **arguments)
    result = nil
    changed = changes_rows?(model) { result = call_tool(name, user: user(viewer), **arguments) }
    [ changed, result ]
  end

  # Asserts the screen and the tool agree for every viewer, and returns who may.
  def assert_parity(model, name, subject_names, page:, tool:)
    allowed = []
    subject_names.each do |subject|
      VIEWERS.each do |viewer|
        on_page = page_changes_rows?(model, as: user(viewer)) { page.call(person(subject)) }
        changed, result = tool_changes?(model, viewer, name, **tool.call(person(subject)))
        assert_equal on_page, changed, "#{name}: #{viewer} for #{subject}: page #{on_page ? "allows" : "refuses"}, tool said #{result.error.inspect}"
        allowed << [ viewer, subject ] if changed
      end
    end
    allowed
  end

  def last_call
    McpToolCall.order(:created_at).last
  end

  # Credit

  def adjust_page(subject, credits: 1)
    post commitment_commitment_adjustments_path(@commitment), params: { commitment_adjustment: { person_id: subject.id, credits: credits, reason: "Ran the raffle" } }
  end

  def adjust_arguments(subject, credits: 1)
    { checklist_id: @checklist.neat_id, item_id: @shifts.neat_id, person_id: subject.neat_id, credits: credits, reason: "Ran the raffle" }
  end

  test "add_credit_adjustment agrees with the page for every viewer" do
    allowed = assert_parity(CommitmentAdjustment, "add_credit_adjustment", %i[alpha_member kid organizer],
      page: ->(subject) { adjust_page(subject) }, tool: ->(subject) { adjust_arguments(subject) })

    assert_includes allowed, [ :organizer, :alpha_member ]
    assert_includes allowed, [ :alpha_manager, :organizer ]
    assert_includes allowed, [ :admin, :kid ]
    assert_not_includes allowed, [ :organizer, :organizer ], "an organizer doesn't adjust their own credit"
    assert_equal %i[admin alpha_manager organizer], allowed.map(&:first).uniq.sort
  end

  test "an organizer adds credit, gets the person's numbers and keeps the reason out of the call log" do
    result = call_tool("add_credit_adjustment", user: user(:organizer), **adjust_arguments(person(:alpha_member), credits: 1))
    adjustment = CommitmentAdjustment.sole

    assert_equal adjustment, result.changed
    assert_equal [ adjustment.neat_id, 2, 2, 0 ], result.value.values_at("adjustment_id", "confirmed", "owed", "remaining")
    assert_equal [ 1, "Ran the raffle", person(:organizer), person(:alpha_member) ], [ adjustment.credits, adjustment.reason, adjustment.created_by, adjustment.person ]
    assert_equal user(:organizer).id, AuditLog.where(item_type: "CommitmentAdjustment", item_id: adjustment.id, event: "create").sole.whodunnit
    assert_equal Mcp::Tool::MASKED, last_call.arguments["reason"]
    assert_not_includes last_call.arguments.to_s, "raffle"

    refresh_checklist
    shifts = call_tool("checklist_status", user: user(:admin), person_id: person(:alpha_member).neat_id, checklist_id: @checklist.neat_id)
      .value["checklists"].sole["items"].find { |cell| cell["item"]["label"] == "Shifts" }
    assert_equal [ "met", 2 ], [ shifts["status"], shifts["measures"]["confirmed"] ]
  end

  test "nobody adjusts credit for themselves or a relative, with the page's message, and a stranger gets nothing to learn" do
    Relationship.create!(parent: person(:organizer), child: person(:kid), relationship_type: @guardianship, created_by: person(:admin))
    reason = "Not allowed: #{Commitment::SELF_APPROVAL_REASON}"

    assert_refused(reason, CommitmentAdjustment) { call_tool("add_credit_adjustment", user: user(:organizer), **adjust_arguments(person(:organizer))) }
    assert_refused(reason, CommitmentAdjustment) { call_tool("add_credit_adjustment", user: user(:organizer), **adjust_arguments(person(:kid))) }
    assert_refused("Not allowed", CommitmentAdjustment) { call_tool("add_credit_adjustment", user: user(:alpha_member), **adjust_arguments(person(:organizer))) }
    assert_refused("Not allowed", CommitmentAdjustment) { call_tool("add_credit_adjustment", user: user(:grant_holder), **adjust_arguments(person(:alpha_member))) }
    assert_refused("Not found", CommitmentAdjustment) { call_tool("add_credit_adjustment", user: user(:beta_member), **adjust_arguments(person(:alpha_member))) }
    assert_nil call_tool("add_credit_adjustment", user: user(:admin), **adjust_arguments(person(:kid))).error
  end

  test "add_credit_adjustment refuses what the form wouldn't take" do
    assert_refused(/Credits must be other than 0/, CommitmentAdjustment) { call_tool("add_credit_adjustment", user: user(:admin), **adjust_arguments(person(:alpha_member), credits: 0)) }
    assert_refused(/Reason can't be blank/, CommitmentAdjustment) { call_tool("add_credit_adjustment", user: user(:admin), **adjust_arguments(person(:alpha_member)), reason: " ") }
    assert_refused("Not found", CommitmentAdjustment) { call_tool("add_credit_adjustment", user: user(:admin), **adjust_arguments(person(:beta_member))) }
    assert_refused("Not found", CommitmentAdjustment) { call_tool("add_credit_adjustment", user: user(:admin), **adjust_arguments(person(:alpha_member)), item_id: @login.neat_id) }
    assert_refused("Not found", CommitmentAdjustment) { call_tool("add_credit_adjustment", user: user(:admin), **adjust_arguments(person(:alpha_member)), item_id: "chli_nope") }
    assert_refused(/greater than/, CommitmentAdjustment) { call_tool("add_credit_adjustment", user: user(:admin), **adjust_arguments(person(:alpha_member), credits: 2**31)) }
    assert_refused(/not allowed|additional|Unknown/i, CommitmentAdjustment) { call_tool("add_credit_adjustment", user: user(:admin), **adjust_arguments(person(:alpha_member)), checklist_title: "x") }
  end

  test "remove_credit_adjustment agrees with the page for every viewer" do
    adjustment = CommitmentAdjustment.create!(commitment: @commitment, person: person(:alpha_member), credits: 1, reason: "Covered", created_by: person(:admin))

    allowed = VIEWERS.select do |viewer|
      on_page = page_changes_rows?(CommitmentAdjustment, as: user(viewer)) { delete commitment_commitment_adjustment_path(@commitment, adjustment) }
      changed, result = tool_changes?(CommitmentAdjustment, viewer, "remove_credit_adjustment", checklist_id: @checklist.neat_id, item_id: @shifts.neat_id, adjustment_id: adjustment.neat_id)
      assert_equal on_page, changed, "#{viewer}: #{result.error.inspect}"
      changed
    end
    assert_equal %i[organizer alpha_manager admin].sort, allowed.sort
  end

  test "remove_credit_adjustment removes it and returns the numbers; an organizer can't remove their own family's" do
    adjustment = CommitmentAdjustment.create!(commitment: @commitment, person: person(:alpha_member), credits: 1, reason: "Covered", created_by: person(:admin))
    own = CommitmentAdjustment.create!(commitment: @commitment, person: person(:organizer), credits: 1, reason: "Covered", created_by: person(:admin))

    assert_refused("Not allowed: #{Commitment::SELF_APPROVAL_REASON}", CommitmentAdjustment) do
      call_tool("remove_credit_adjustment", user: user(:organizer), checklist_id: @checklist.neat_id, item_id: @shifts.neat_id, adjustment_id: own.neat_id)
    end
    result = call_tool("remove_credit_adjustment", user: user(:organizer), checklist_id: @checklist.neat_id, item_id: @shifts.neat_id, adjustment_id: adjustment.neat_id)
    assert_equal [ adjustment.neat_id, 1 ], result.value.values_at("removed_adjustment_id", "confirmed")
    assert_not CommitmentAdjustment.exists?(adjustment.id)
    assert_equal adjustment, result.changed
    assert Mcp.tool("remove_credit_adjustment").annotations[:destructive_hint]
    assert_equal "Not found", call_tool("remove_credit_adjustment", user: user(:organizer), checklist_id: @checklist.neat_id, item_id: @shifts.neat_id, adjustment_id: adjustment.neat_id).error
  end

  # Excuses

  def excuse_page(subject, item: @login)
    post checklist_checklist_excuses_path(@checklist), params: { checklist_excuse: { item_id: item.id, person_id: subject.id, reason: "Ill" } }
  end

  def excuse_arguments(subject, item: @login)
    { checklist_id: @checklist.neat_id, item_id: item.neat_id, person_id: subject.neat_id, reason: "Ill" }
  end

  test "excuse_item agrees with the page for every viewer, self and relatives included" do
    Relationship.create!(parent: person(:alpha_manager), child: person(:kid), relationship_type: @guardianship, created_by: person(:admin))
    allowed = assert_parity(ChecklistExcuse, "excuse_item", %i[alpha_member kid alpha_manager],
      page: ->(subject) { excuse_page(subject) }, tool: ->(subject) { excuse_arguments(subject) })

    assert_includes allowed, [ :alpha_manager, :alpha_member ]
    assert_includes allowed, [ :admin, :kid ]
    assert_includes allowed, [ :admin, :alpha_manager ]
    assert_not_includes allowed, [ :alpha_manager, :alpha_manager ]
    assert_not_includes allowed, [ :alpha_manager, :kid ]
    assert_equal %i[admin alpha_manager], allowed.map(&:first).uniq.sort
  end

  test "a manager excuses a person: reason masked in the log, shown to managers only, and removable" do
    result = call_tool("excuse_item", user: user(:alpha_manager), **excuse_arguments(person(:alpha_member)), expires_on: (Date.current + 1.month).iso8601)
    excuse = ChecklistExcuse.sole

    assert_equal excuse, result.changed
    assert_equal [ excuse.neat_id, @login.neat_id, person(:alpha_member).neat_id ], [ result.value["excuse_id"], result.value["item"]["id"], result.value["person"]["id"] ]
    assert_equal [ "Ill", Date.current + 1.month, person(:alpha_manager) ], [ excuse.reason, excuse.expires_on, excuse.created_by ]
    assert_equal user(:alpha_manager).id, AuditLog.where(item_type: "ChecklistExcuse", item_id: excuse.id, event: "create").sole.whodunnit
    assert_equal Mcp::Tool::MASKED, last_call.arguments["reason"]

    refresh_checklist
    cell = ->(viewer) { call_tool("checklist_status", user: user(viewer), person_id: person(:alpha_member).neat_id, checklist_id: @checklist.neat_id).value["checklists"].sole["items"].find { |c| c["item"]["label"] == "Login" } }
    assert_equal [ "exempt", "Excused" ], cell.call(:alpha_manager).values_at("status", "text")
    assert_equal [ "Ill", excuse.neat_id ], cell.call(:alpha_manager)["excuse"].values_at("reason", "excuse_id")
    assert_nil cell.call(:alpha_member)["excuse"]&.dig("reason"), "the reason is for managers and admins"
    granted = call_tool("checklist_status", user: user(:grant_holder), person_id: person(:alpha_member).neat_id, checklist_id: @checklist.neat_id)
    assert_nil granted.value["checklists"].sole["items"].find { |c| c["item"]["label"] == "Login" }["excuse"]&.dig("reason")

    removal = call_tool("remove_excuse", user: user(:alpha_manager), checklist_id: @checklist.neat_id, excuse_id: excuse.neat_id)
    assert_equal [ excuse.neat_id, "Login" ], [ removal.value["removed_excuse_id"], removal.value["item"]["label"] ]
    assert_not ChecklistExcuse.exists?(excuse.id)
  end

  test "self and relatives are refused with the model's message; non-managers get Not allowed, strangers Not found" do
    Relationship.create!(parent: person(:alpha_manager), child: person(:kid), relationship_type: @guardianship, created_by: person(:admin))
    reason = "Not allowed: #{ChecklistExcuse::SELF_REASON}"

    assert_refused(reason, ChecklistExcuse) { call_tool("excuse_item", user: user(:alpha_manager), **excuse_arguments(person(:alpha_manager))) }
    assert_refused(reason, ChecklistExcuse) { call_tool("excuse_item", user: user(:alpha_manager), **excuse_arguments(person(:kid))) }
    assert_refused("Not allowed", ChecklistExcuse) { call_tool("excuse_item", user: user(:organizer), **excuse_arguments(person(:alpha_member))) }
    assert_refused("Not allowed", ChecklistExcuse) { call_tool("excuse_item", user: user(:grant_holder), **excuse_arguments(person(:beta_member))) } # no look-up for someone who can't excuse
    assert_refused("Not allowed", ChecklistExcuse) { call_tool("excuse_item", user: user(:alpha_member), **excuse_arguments(person(:alpha_member))) }
    assert_refused("Not found", ChecklistExcuse) { call_tool("excuse_item", user: user(:beta_member), **excuse_arguments(person(:alpha_member))) }
    assert_refused("Not found", ChecklistExcuse) { call_tool("excuse_item", user: user(:admin), **excuse_arguments(person(:beta_member))) }
    assert_refused(/Reason can't be blank/, ChecklistExcuse) { call_tool("excuse_item", user: user(:admin), **excuse_arguments(person(:alpha_member)), reason: "") }
    assert_refused("expires_on must be a date, YYYY-MM-DD", ChecklistExcuse) { call_tool("excuse_item", user: user(:admin), **excuse_arguments(person(:alpha_member)), expires_on: "someday") }
    assert_refused("Pick one of this item's meetings", ChecklistExcuse) { call_tool("excuse_item", user: user(:admin), **excuse_arguments(person(:alpha_member)), event_id: create_world_event("Other", @alpha, 1.day.ago).neat_id) }
  end

  test "an archived checklist takes no excuse, as the page refuses" do
    @checklist.update!(status: :archived)
    on_page = page_changes_rows?(ChecklistExcuse, as: user(:admin)) { excuse_page(person(:alpha_member)) }
    assert_not on_page
    assert_refused("Not allowed", ChecklistExcuse) { call_tool("excuse_item", user: user(:admin), **excuse_arguments(person(:alpha_member))) }
  end

  test "remove_excuse agrees with the page for every viewer" do
    excuse = ChecklistExcuse.create!(item: @login, person: person(:alpha_member), reason: "Ill", created_by: person(:admin))

    allowed = VIEWERS.select do |viewer|
      on_page = page_changes_rows?(ChecklistExcuse, as: user(viewer)) { delete checklist_checklist_excuse_path(@checklist, excuse) }
      changed, result = tool_changes?(ChecklistExcuse, viewer, "remove_excuse", checklist_id: @checklist.neat_id, excuse_id: excuse.neat_id)
      assert_equal on_page, changed, "#{viewer}: #{result.error.inspect}"
      changed
    end
    assert_equal %i[admin alpha_manager], allowed.sort
    assert_refused("Not found", ChecklistExcuse) { call_tool("remove_excuse", user: user(:admin), checklist_id: @checklist.neat_id, excuse_id: "chlx_nope") }
    assert Mcp.tool("remove_excuse").annotations[:destructive_hint]
  end

  test "excuse_item excuses one meeting of an attendance item, as the page does, and not one already excused" do
    travel_to Time.zone.parse("2026-10-10 12:00") do
      checklist = Checklist.create!(title: "Attendance", team: @alpha, status: :active, starts_on: Date.new(2026, 9, 1), created_by: person(:admin))
      checklist.checklist_rules.create!(effect: :include, target_type: :team, team: @alpha)
      period = TimeClockPeriod.create!(name: "Season", start_time: Date.new(2026, 9, 1), end_time: Date.new(2027, 6, 30), permission: :added_by_admin)
      meetings = [ [ "Kickoff", "2026-10-05" ], [ "Build night", "2026-10-07" ] ].map do |name, day|
        Event.create!(name: name, event_type: event_types(:one), team: @alpha, time_clock_period: period,
          start_time: Time.zone.parse("#{day} 18:00"), end_time: Time.zone.parse("#{day} 20:00"))
      end
      item = checklist.checklist_items.new(kind: "attendance", label: "Attendance")
      item.config_params = { rules: [ { name: "Fall", share: "60" } ] }
      item.save!
      arguments = { checklist_id: checklist.neat_id, item_id: item.neat_id, person_id: person(:alpha_member).neat_id, reason: "Ill", event_id: meetings.last.neat_id }

      on_page = page_changes_rows?(ChecklistExcuse, as: user(:admin)) do
        post checklist_checklist_excuses_path(checklist), params: { checklist_excuse: { item_id: item.id, person_id: person(:alpha_member).id, event_id: meetings.last.id, reason: "Ill" } }
      end
      assert on_page

      result = call_tool("excuse_item", user: user(:alpha_manager), **arguments)
      assert_nil result.error
      assert_equal [ meetings.last, nil ], [ ChecklistExcuse.sole.event, ChecklistExcuse.sole.expires_on ]
      assert_equal [ meetings.last.neat_id, "Build night" ], result.value["event"].values_at("id", "name")

      assert_refused("Pick one of this item's meetings", ChecklistExcuse) { call_tool("excuse_item", user: user(:alpha_manager), **arguments) }
      Checklists::Refresher.new(checklist, silent: true).call
      assert_refused("Not allowed", ChecklistExcuse) { call_tool("excuse_item", user: user(:alpha_member), **arguments, event_id: meetings.first.neat_id) }
    end
  end

  # Attestation

  def attest_page(subject)
    post checklist_checklist_attestations_path(@checklist), params: { item_id: @handbook.id, person_id: subject.id }
  end

  def attest_arguments(subject)
    { checklist_id: @checklist.neat_id, item_id: @handbook.neat_id, person_id: subject.neat_id }
  end

  test "attest_item agrees with the page for every viewer" do
    allowed = assert_parity(ChecklistAttestation, "attest_item", %i[alpha_member kid alpha_manager],
      page: ->(subject) { attest_page(subject) }, tool: ->(subject) { attest_arguments(subject) })

    assert_includes allowed, [ :alpha_member, :alpha_member ]
    assert_includes allowed, [ :kid_parent, :kid ]
    assert_includes allowed, [ :admin, :kid ]
    assert_not_includes allowed, [ :alpha_manager, :alpha_member ], "this item is confirmed by a guardian or the person, not a manager"
    assert_not_includes allowed, [ :alpha_member, :kid ]
  end

  test "attest_item records who confirmed it and what, and a manager item refuses the person themselves" do
    result = call_tool("attest_item", user: user(:kid_parent), **attest_arguments(person(:kid)))
    attestation = ChecklistAttestation.sole

    assert_equal attestation, result.changed
    assert_equal [ attestation.neat_id, "Handbook read" ], result.value.values_at("attestation_id", "statement")
    assert_equal [ person(:kid), person(:kid_parent), "guardian", "handbook-read" ], [ attestation.person, attestation.attested_by, attestation.attested_as, attestation.key ]
    assert_equal user(:kid_parent).id, AuditLog.where(item_type: "ChecklistAttestation", item_id: attestation.id, event: "create").sole.whodunnit

    managed = add_checklist_item(:attested, "Physical", { statement: "Physical on file", attested_by: "manager" })
    assert_refused("Not allowed", ChecklistAttestation) { call_tool("attest_item", user: user(:kid_parent), **attest_arguments(person(:kid)), item_id: managed.neat_id) }
    assert_refused("Not allowed", ChecklistAttestation) { call_tool("attest_item", user: user(:alpha_manager), **attest_arguments(person(:alpha_manager)), item_id: managed.neat_id) }
    assert_nil call_tool("attest_item", user: user(:alpha_manager), **attest_arguments(person(:alpha_member)), item_id: managed.neat_id).error
  end

  test "attest_item only finds confirmed items and people the checklist covers" do
    assert_refused("Not found", ChecklistAttestation) { call_tool("attest_item", user: user(:admin), **attest_arguments(person(:alpha_member)), item_id: @login.neat_id) }
    assert_refused("Not found", ChecklistAttestation) { call_tool("attest_item", user: user(:admin), **attest_arguments(person(:beta_member))) }
    assert_refused("Not found", ChecklistAttestation) { call_tool("attest_item", user: user(:beta_member), **attest_arguments(person(:beta_member))) }
    @checklist.update!(status: :archived)
    assert_refused("Not allowed", ChecklistAttestation) { call_tool("attest_item", user: user(:admin), **attest_arguments(person(:alpha_member))) }
  end

  # Recorded lists and copies

  test "record_list agrees with the page for every viewer and keeps the note out of the log" do
    allowed = VIEWERS.select do |viewer|
      on_page = page_changes_rows?(ChecklistList, as: user(viewer)) { post checklist_checklist_lists_path(@checklist), params: { checklist_list: { note: "Trip" } } }
      changed, result = tool_changes?(ChecklistList, viewer, "record_list", checklist_id: @checklist.neat_id, note: "Trip")
      assert_equal on_page, changed, "#{viewer}: #{result.error.inspect}"
      changed
    end
    assert_equal %i[organizer alpha_manager admin].sort, allowed.sort

    result = call_tool("record_list", user: user(:organizer), checklist_id: @checklist.neat_id, note: "Spring trip roster")
    list = ChecklistList.sole
    assert_equal list, result.changed
    assert_equal [ list.neat_id, "Spring trip roster", list.rows.size ], result.value.values_at("id", "note", "people")
    assert_equal person(:organizer), list.recorded_by
    assert_equal Mcp::Tool::MASKED, last_call.arguments["note"]
    @checklist.update!(status: :archived)
    assert_refused("Not allowed", ChecklistList) { call_tool("record_list", user: user(:admin), checklist_id: @checklist.neat_id) }
  end

  test "copy_checklist agrees with the page for every viewer and makes a draft" do
    allowed = VIEWERS.select do |viewer|
      on_page = page_changes_rows?(Checklist, as: user(viewer)) { post copy_checklist_path(@checklist), params: { title: "Eligibility next", shift_months: 12 } }
      changed, result = tool_changes?(Checklist, viewer, "copy_checklist", checklist_id: @checklist.neat_id, title: "Eligibility next")
      assert_equal on_page, changed, "#{viewer}: #{result.error.inspect}"
      changed
    end
    assert_equal %i[organizer alpha_manager admin].sort, allowed.sort

    result = call_tool("copy_checklist", user: user(:alpha_manager), checklist_id: @checklist.neat_id, title: "Eligibility next", shift_months: 12)
    copy = Checklist.find_by!(title: "Eligibility next")
    assert_equal copy, result.changed
    assert_equal [ copy.neat_id, "draft", person(:alpha_manager) ], [ result.value["checklist"]["id"], result.value["checklist"]["status"], copy.created_by ]
    assert_equal @checklist.checklist_items.order(:position).map(&:label), copy.checklist_items.order(:position).map(&:label)
    assert_equal @checklist.starts_on + 12.months, copy.starts_on
    assert_equal [ 0, [ "Safety 2026" ] ], result.value.values_at("left_out_rules", "kept"), "the safety badge item names a year and has no successor"
    assert_equal "Eligibility (copy)", Checklist.find(call_tool("copy_checklist", user: user(:admin), checklist_id: @checklist.neat_id, shift_months: 0).changed.id).title
  end

  test "copy_checklist swaps year-named badges for the next year's and says which it couldn't" do
    next_safety = create_world_badge("Safety 2027")
    create_world_badge("Handbook 2026")
    @checklist.checklist_rules.create!(effect: :exclude, target_type: :badge, badge: @safety)
    @checklist.checklist_rules.create!(effect: :exclude, target_type: :badge, badge: Badge.find_by!(name: "Handbook 2026"))

    result = call_tool("copy_checklist", user: user(:admin), checklist_id: @checklist.neat_id)
    copy = Checklist.find_by!(title: "Eligibility (copy)")

    assert_includes copy.checklist_rules.map(&:badge_id), next_safety.id
    assert_not_includes copy.checklist_rules.map(&:badge_id), @safety.id
    assert_includes result.value["kept"], "Handbook 2026"
    assert_equal "Not found", call_tool("copy_checklist", user: user(:beta_member), checklist_id: @checklist.neat_id).error
    assert_equal "Not allowed", call_tool("copy_checklist", user: user(:alpha_member), checklist_id: @checklist.neat_id).error
    assert_equal "Not allowed", call_tool("copy_checklist", user: user(:grant_holder), checklist_id: @checklist.neat_id).error
  end

  test "the write tools need writes enabled and the checklists feature" do
    %w[add_credit_adjustment remove_credit_adjustment excuse_item remove_excuse attest_item copy_checklist record_list].each do |name|
      assert Mcp.tool(name).write?, name
      assert_equal [ :checklists ], Mcp.tool(name).features, name
      assert_equal "Writes disabled", call_tool(name, user: user(:admin), writes_enabled: false, checklist_id: @checklist.neat_id, item_id: @login.neat_id,
        person_id: person(:kid).neat_id, adjustment_id: "x", excuse_id: "x", credits: 1, reason: "x").error, name
    end
    with_feature(:checklists, false) do
      assert_equal "Feature off", call_tool("record_list", user: user(:admin), checklist_id: @checklist.neat_id).error
      assert_equal "Feature off", call_tool("list_checklists", user: user(:admin)).error
    end
  end
end
