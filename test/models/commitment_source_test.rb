require "test_helper"
require_relative "../support/commitments_world"

class CommitmentSourceTest < ActiveSupport::TestCase
  include CommitmentsWorld

  setup do
    build_commitments_world
    @commitment = create_world_commitment
  end

  test "needs a registered kind, a subject of the kind's type and a positive ratio" do
    assert_not @commitment.commitment_sources.build(kind: "nonsense", subject: @outreach).valid?
    assert_not @commitment.commitment_sources.build(kind: "checkins").valid?
    assert_not @commitment.commitment_sources.build(kind: "checkins", subject: @club).valid?
    assert_not @commitment.commitment_sources.build(kind: "checkins", subject: @outreach, per: 0).valid?
    assert_not @commitment.commitment_sources.build(kind: "checkins", subject: @outreach, max_credits: 0).valid?
    assert @commitment.commitment_sources.build(kind: "checkins", subject: @outreach).valid?
  end

  test "new sources go last" do
    first = @commitment.commitment_sources.create!(kind: "checkins", subject: @outreach)
    second = @commitment.commitment_sources.create!(kind: "checkins", subject: @meeting)
    assert_equal [ 1, 2 ], [ first.position, second.position ]
    assert_equal [ first, second ], @commitment.commitment_sources.to_a
  end

  test "label, ratio text and how to earn with upcoming events" do
    travel_to Time.zone.parse("2026-10-05 12:00") do
      source = @commitment.commitment_sources.create!(kind: "checkins", subject: @outreach, per: 3)
      create_world_event("Past", "2026-10-02 10:00")
      create_world_event("Next", "2026-10-10 10:00")

      assert_equal "Check-ins: Outreach", source.label
      assert_equal "3 count as 1", source.ratio_text
      how = source.kind_instance.how_to_earn
      assert_equal "Check in at any Outreach event", how.text
      assert_equal [ "Next, Sat Oct 10" ], how.links.map(&:first)
    end
  end
end
