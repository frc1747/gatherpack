require "test_helper"
require_relative "../support/commitments_world"

class CommitmentAdjustmentTest < ActiveSupport::TestCase
  include CommitmentsWorld

  setup do
    build_commitments_world
    @commitment = create_world_commitment
  end

  test "is for someone who owes, with nonzero credits and a reason" do
    assert_not @commitment.commitment_adjustments.build(person: person(:outsider), credits: 1, reason: "x").valid?
    assert_not @commitment.commitment_adjustments.build(person: person(:member), credits: 0, reason: "x").valid?
    assert_not @commitment.commitment_adjustments.build(person: person(:member), credits: 1, reason: "").valid?
    assert @commitment.commitment_adjustments.build(person: person(:member), credits: -1, reason: "Left early").valid?
  end

  test "debits lower confirmed credit" do
    @commitment.commitment_adjustments.create!(person: person(:member), credits: 3, reason: "Ran the raffle")
    @commitment.commitment_adjustments.create!(person: person(:member), credits: -1, reason: "Counted twice")

    progress = @commitment.progress_for(person(:member))
    assert_equal 2, progress.confirmed
    assert progress.met?
  end
end
