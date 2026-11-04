require "test_helper"
require_relative "../../../support/mcp_commitments_world"

class Mcp::Tools::CommitmentAdjustmentToolsTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers
  include McpCommitmentsWorld

  setup do
    host! "localhost"
    build_mcp_world
    build_mcp_commitments_world
    @ward_adjustment = CommitmentAdjustment.find_by!(person: person(:ward))
  end

  def add(viewer, target, credits: 1, reason: "Ran the raffle", commitment: @shifts, **options)
    call_tool("add_commitment_adjustment", user: user(viewer), commitment_id: commitment.neat_id, person_id: person(target).neat_id,
      credits: credits, reason: reason, **options)
  end

  def remove(viewer, adjustment = @ward_adjustment, **options)
    call_tool("remove_commitment_adjustment", user: user(viewer), adjustment_id: adjustment.neat_id, **options)
  end

  def progress(viewer, **arguments)
    call_tool("commitment_progress", user: user(viewer), commitment_id: @shifts.neat_id, **arguments)
  end

  # Asserts the block is refused with error and changes no adjustment and no audit row.
  def assert_unchanged(error)
    rows = CommitmentAdjustment.order(:id).pluck(:id, :credits, :reason)
    versions = AuditLog.count
    result = yield
    assert_nil result.changed
    error.is_a?(Regexp) ? assert_match(error, result.error.to_s) : assert_equal(error, result.error)
    assert_equal rows, CommitmentAdjustment.order(:id).pluck(:id, :credits, :reason)
    assert_equal versions, AuditLog.count
  end

  # Make the organizer a relative of sibling, who is in ward's group.
  def relate_organizer_to_sibling
    Relationship.create!(parent: person(:organizer), child: person(:sibling), relationship_type: @friend, created_by: person(:admin))
  end

  test "an organizer, a team manager and an admin add an adjustment and get the person's progress" do
    { organizer: :alpha_member, alpha_manager: :sibling, admin: :alpha_member }.each do |viewer, target|
      result = assert_difference("CommitmentAdjustment.count", 1) { add(viewer, target, credits: 2, reason: "Ran the raffle") }
      adjustment = CommitmentAdjustment.order(:created_at).last

      assert_equal adjustment, result.changed
      assert_equal adjustment.neat_id, result.value["adjustment_id"]
      assert_equal [ 2, "Ran the raffle", user(viewer).person ], [ adjustment.credits, adjustment.reason, adjustment.created_by ], viewer
      assert_equal person(target), adjustment.person
      added = result.value["rows"].sole["adjustments"].find { |a| a["adjustment_id"] == adjustment.neat_id }
      assert_equal [ 2, "Ran the raffle", person(target).neat_id ], [ added["credits"], added["reason"], added["person"]["id"] ], viewer
      assert_equal @shifts.progress_for(person(target)).confirmed, result.value["rows"].sole["confirmed"]
      assert_equal user(viewer).id, AuditLog.where(item_type: "CommitmentAdjustment", item_id: adjustment.id, event: "create").sole.whodunnit
    end
  end

  test "a negative number takes credit away" do
    assert_difference("CommitmentAdjustment.count", 1) { assert_nil add(:organizer, :alpha_member, credits: -1).error }
    assert_equal(-1, CommitmentAdjustment.order(:created_at).last.credits)
  end

  test "a member who owes it, a guardian and a plain member are refused, by whether they can see it" do
    assert_unchanged("Not allowed") { add(:alpha_member, :alpha_member) }
    assert_unchanged("Not allowed") { add(:alpha_member, :sibling) }
    assert_unchanged("Not allowed") { add(:ward, :ward) }
    assert_unchanged("Not allowed") { add(:guardian, :ward) }
    assert_unchanged("Not allowed") { add(:guardian, :beta_member) }
    assert_unchanged("Not found") { add(:beta_member, :alpha_member) }
    assert_unchanged("Not found") { add(:badge_holder, :alpha_member) }
    assert_unchanged("Not found") { add(:alpha_manager, :alpha_member, commitment: @beta_shifts) }
  end

  test "a listed organizer who lost the badge, and a manager of another team, don't run it" do
    assert_unchanged("Not allowed") { add(:lapsed, :alpha_member) }
    assert_unchanged("Not found") { add(:organizer, :beta_member, commitment: @beta_shifts) }
  end

  test "nobody adjusts credit for themselves, a relative, or anyone in a group with either" do
    relate_organizer_to_sibling
    reason = "Not allowed: #{Commitment::SELF_APPROVAL_REASON}"

    assert_unchanged(reason) { add(:organizer, :organizer) }
    assert_unchanged(reason) { add(:organizer, :sibling) }
    assert_unchanged(reason) { add(:organizer, :ward) }
    assert_unchanged(reason) { add(:alpha_manager, :alpha_manager) }
    assert_unchanged(reason) { remove(:organizer) }
    assert_nil add(:organizer, :alpha_member).error
    assert_nil add(:admin, :ward).error
    assert_nil add(:alpha_manager, :ward).error
  end

  test "a person who doesn't owe it, or doesn't exist, is not found, and isn't looked up for a member" do
    assert_unchanged("Not found") { add(:admin, :beta_member) }
    assert_unchanged("Not found") { add(:admin, :guardian) }
    assert_unchanged("Not found") { add(:organizer, :badge_holder) }
    assert_unchanged("Not found") { call_tool("add_commitment_adjustment", user: user(:admin), commitment_id: @shifts.neat_id, person_id: "per_nope", credits: 1, reason: "x") }
    assert_unchanged("Not found") { call_tool("add_commitment_adjustment", user: user(:admin), commitment_id: @shifts.neat_id, person_id: @shifts.neat_id, credits: 1, reason: "x") }
    assert_unchanged("Not found") { call_tool("add_commitment_adjustment", user: user(:admin), commitment_id: person(:ward).neat_id, person_id: person(:ward).neat_id, credits: 1, reason: "x") }
    assert_unchanged("Not allowed") { add(:alpha_member, :beta_member) }
  end

  test "credits must be a whole JSON number other than zero that fits, and a reason is needed" do
    assert_unchanged(/Credits must be other than 0/) { add(:admin, :alpha_member, credits: 0) }
    assert_unchanged(/Reason can't be blank/) { add(:admin, :alpha_member, reason: "") }
    assert_unchanged(/Reason can't be blank/) { add(:admin, :alpha_member, reason: "  ") }
    { 1.5 => /not an integer/, "2" => /not an integer/, nil => /not an integer/, true => /not an integer/,
      2.0 => /must be an integer/, 2**31 => /greater than/, -(2**31) - 1 => /less than/ }.each do |credits, error|
      assert_unchanged(error) { add(:admin, :alpha_member, credits: credits) }
    end
    assert_equal "credits is out of range", add(:admin, :alpha_member, credits: Float::INFINITY).error
    assert_nil add(:admin, :alpha_member, credits: 2**31 - 1).error
  end

  test "removal is marked destructive" do
    assert Mcp.tool("remove_commitment_adjustment").annotations[:destructive_hint]
  end

  test "a closed schema refuses other arguments by name" do
    assert_unchanged(/created_by/) { add(:admin, :alpha_member, created_by: person(:ward).neat_id) }
  end

  test "a read token, writes off and the feature off refuse it" do
    assert_unchanged("Not allowed") { add(:admin, :alpha_member, scopes: "mcp_read") }
    assert_unchanged("Writes disabled") { add(:admin, :alpha_member, writes_enabled: false) }
    assert_unchanged("Not allowed") { remove(:admin, scopes: "mcp_read") }
    assert_unchanged("Writes disabled") { remove(:admin, writes_enabled: false) }
    with_settings(feature_commitments: "false") do
      assert_unchanged(/\S/) { add(:admin, :alpha_member) }
      assert_unchanged(/\S/) { remove(:admin) }
    end
  end

  test "hooks run on both" do
    assert_hook_runs("commitment_adjustments - create") { add(:admin, :alpha_member) }
    assert_hook_runs("commitment_adjustments - destroy") { remove(:admin) }
  end

  test "an organizer sees adjustment_id on exactly the adjustments they may remove" do
    relate_organizer_to_sibling
    other = CommitmentAdjustment.create!(commitment: @shifts, person: person(:alpha_member), credits: 1, reason: "Other", created_by: person(:admin))

    ids = ->(viewer) { progress(viewer).value["rows"].flat_map { |row| row["adjustments"] }.filter_map { |a| a["adjustment_id"] } }
    assert_equal [ other.neat_id, @ward_adjustment.neat_id ].sort, ids.call(:admin).sort
    assert_equal [ other.neat_id ], ids.call(:organizer)
    assert_equal [ other.neat_id, @ward_adjustment.neat_id ].sort, ids.call(:alpha_manager).sort
    [ :ward, :guardian, :alpha_member, :lapsed ].each { |viewer| assert_empty ids.call(viewer), viewer }
    assert_equal [ "Covered a shift" ], progress(:ward).value["rows"].sole["adjustments"].map { |a| a["reason"] }
    assert_nil progress(:ward).value["rows"].sole["adjustments"].first["adjustment_id"]
  end

  test "an organizer, a manager and an admin remove one, and get the person's progress" do
    [ :organizer, :alpha_manager, :admin ].each do |viewer|
      adjustment = CommitmentAdjustment.create!(commitment: @shifts, person: person(:alpha_member), credits: 3, reason: "Again", created_by: person(:admin))
      result = assert_difference("CommitmentAdjustment.count", -1) { remove(viewer, adjustment) }

      assert_equal adjustment, result.changed
      assert_equal adjustment.neat_id, result.value["removed_adjustment_id"]
      assert_empty result.value["rows"].sole["adjustments"]
      assert_equal 1, result.value["rows"].sole["confirmed"]
      assert_equal user(viewer).id, AuditLog.where(item_type: "CommitmentAdjustment", item_id: adjustment.id, event: "destroy").sole.whodunnit
    end
  end

  test "removing one for a person who no longer owes it still succeeds" do
    adjustment = CommitmentAdjustment.create!(commitment: @shifts, person: person(:alpha_member), credits: 3, reason: "Again", created_by: person(:admin))
    Membership.where(person: person(:alpha_member)).destroy_all

    result = remove(:admin, adjustment)
    assert_nil result.error
    assert_empty result.value["rows"]
    assert_not CommitmentAdjustment.exists?(adjustment.id)
  end

  test "removal is refused for those who can't remove it on the page" do
    beta_adjustment = CommitmentAdjustment.create!(commitment: @beta_shifts, person: person(:beta_member), credits: 1, reason: "B")
    assert_unchanged("Not allowed") { remove(:ward) }
    assert_unchanged("Not allowed") { remove(:guardian) }
    assert_unchanged("Not allowed") { remove(:alpha_member) }
    assert_unchanged("Not allowed") { remove(:lapsed) }
    assert_unchanged("Not found") { remove(:beta_member) }
    assert_unchanged("Not found") { remove(:alpha_manager, beta_adjustment) }
    assert_unchanged("Not found") { call_tool("remove_commitment_adjustment", user: user(:admin), adjustment_id: @shifts.neat_id) }
    assert_unchanged("Not found") { call_tool("remove_commitment_adjustment", user: user(:admin), adjustment_id: "cmad_nope") }
  end

  # The same request through the page and through the tool.
  test "it allows and refuses as the page does" do
    relate_organizer_to_sibling
    [
      [ :admin, :alpha_member, true ],
      [ :alpha_manager, :alpha_member, true ],
      [ :organizer, :alpha_member, true ],
      [ :organizer, :organizer, false ],
      [ :organizer, :sibling, false ],
      [ :organizer, :ward, false ],
      [ :alpha_manager, :alpha_manager, false ],
      [ :lapsed, :alpha_member, false ],
      [ :alpha_member, :alpha_member, false ],
      [ :guardian, :ward, false ],
      [ :beta_member, :alpha_member, false ],
      [ :admin, :beta_member, false ],
      [ :organizer, :guardian, false ]
    ].each do |viewer, target, allowed|
      page = changes_rows?(CommitmentAdjustment) do
        sign_in user(viewer)
        post commitment_commitment_adjustments_path(@shifts), params: { commitment_adjustment: { person_id: person(target).id, credits: 2, reason: "Same" } }
        sign_out user(viewer)
      end
      tool = changes_rows?(CommitmentAdjustment) { add(viewer, target, credits: 2, reason: "Same") }

      assert_equal allowed, page, "page: #{viewer} adjusting #{target}"
      assert_equal page, tool, "tool: #{viewer} adjusting #{target}"
    end
  end

  test "removal allows and refuses as the page does" do
    relate_organizer_to_sibling
    other = CommitmentAdjustment.create!(commitment: @shifts, person: person(:alpha_member), credits: 1, reason: "Other", created_by: person(:admin))
    [
      [ :admin, @ward_adjustment, true ], [ :alpha_manager, @ward_adjustment, true ], [ :organizer, other, true ],
      [ :organizer, @ward_adjustment, false ], [ :ward, @ward_adjustment, false ], [ :guardian, @ward_adjustment, false ],
      [ :alpha_member, other, false ], [ :lapsed, other, false ], [ :beta_member, other, false ]
    ].each do |viewer, adjustment, allowed|
      page = changes_rows?(CommitmentAdjustment) do
        sign_in user(viewer)
        delete commitment_commitment_adjustment_path(@shifts, adjustment)
        sign_out user(viewer)
      end
      tool = changes_rows?(CommitmentAdjustment) { remove(viewer, adjustment) }

      assert_equal allowed, page, "page: #{viewer} removing"
      assert_equal page, tool, "tool: #{viewer} removing"
    end
  end

  test "the reason is masked in the call log and filtered from the Rails log" do
    add(:admin, :alpha_member, reason: "Reasonsecret")
    logged = McpToolCall.order(:created_at).last

    assert_equal "add_commitment_adjustment", logged.tool
    assert_not_includes logged.attributes.values.map(&:to_s).join, "Reasonsecret"
    assert_includes logged.arguments.to_s, @shifts.neat_id

    io = StringIO.new
    sink = ActiveSupport::Logger.new(io, level: :info)
    Rails.logger.broadcast_to(sink)
    with_settings(mcp_write_enabled: "true") do
      mcp_post(mcp_token(user(:admin), scopes: "mcp_read mcp_write"), "tools/call",
        { name: "add_commitment_adjustment", arguments: { commitment_id: @shifts.neat_id, person_id: person(:alpha_member).neat_id, credits: 1, reason: "Reasonsecret" } })
    end
    assert_includes io.string, "Parameters"
    assert_includes io.string, @shifts.neat_id
    assert_not_includes io.string, "Reasonsecret"
    assert_equal "Reasonsecret", CommitmentAdjustment.order(:created_at).last.reason
  ensure
    Rails.logger.stop_broadcasting_to(sink) if sink
  end
end
