require "test_helper"
require_relative "../support/commitments_world"

class CommitmentPolicyTest < ActiveSupport::TestCase
  include CommitmentsWorld

  setup do
    build_commitments_world
    @commitment = create_world_commitment
  end

  test "create: admins, team managers, and grant holders for teams in reach" do
    with_organizer_grants("Commitment Organizer > Club") do
      assert policy(:admin, Commitment.new(team: @other_org)).create?
      assert policy(:crew_manager, Commitment.new(team: @crew)).create?
      assert_not policy(:crew_manager, Commitment.new(team: @club)).create?
      assert policy(:organizer, Commitment.new(team: @club)).create?
      assert_not policy(:organizer, Commitment.new(team: @org)).create?, "above the grant's highest team"
      assert_not policy(:member, Commitment.new(team: @members)).create?
      assert policy(:organizer, Commitment).new?
      assert_not policy(:member, Commitment).new?
    end
  end

  test "manage and progress: organizers only" do
    with_organizer_grants("Commitment Organizer > Club") do
      assert_not policy(:organizer, @commitment).manage?
      @commitment.commitment_organizers.create!(person: person(:organizer))

      assert policy(:organizer, @commitment).manage?
      assert policy(:organizer, @commitment).progress?
      assert policy(:admin, @commitment).progress?
      assert_not policy(:member, @commitment).progress?
      assert_not policy(:crew_manager, @commitment).manage?
    end
  end

  test "show and scope: organizers, and the people who owe" do
    assert policy(:member, @commitment).show?
    assert_not policy(:outsider, @commitment).show?
    assert_not policy(:organizer, @commitment).show?

    assert_equal [ @commitment ], CommitmentPolicy::Scope.new(person(:member).user, Commitment).resolve.to_a
    assert_equal [], CommitmentPolicy::Scope.new(person(:outsider).user, Commitment).resolve.to_a
    with_organizer_grants("Commitment Organizer > Club") do
      @commitment.commitment_organizers.create!(person: person(:organizer))
      assert_equal [ @commitment ], CommitmentPolicy::Scope.new(person(:organizer).user, Commitment).resolve.to_a
    end
  end

  # Decision 14: no approving yourself or your relatives.
  test "nobody adjusts credit for themselves or a relative" do
    with_organizer_grants("Commitment Organizer > Club") do
      @commitment.commitment_organizers.create!(person: person(:organizer))
      for_member = CommitmentAdjustmentPolicy.new(person(:organizer).user, CommitmentAdjustment.new(commitment: @commitment, person: person(:member)))
      for_kid = CommitmentAdjustmentPolicy.new(person(:organizer).user, CommitmentAdjustment.new(commitment: @commitment, person: person(:kid)))

      assert for_member.create?
      assert_not for_kid.create?
      assert_not for_kid.destroy?
      assert_equal Commitment::SELF_APPROVAL_REASON, for_kid.self_approval_reason
      assert_nil for_member.self_approval_reason

      admin_for_kid = CommitmentAdjustmentPolicy.new(person(:admin).user, CommitmentAdjustment.new(commitment: @commitment, person: person(:kid)))
      assert admin_for_kid.create?
      assert_not CommitmentAdjustmentPolicy.new(person(:member).user, CommitmentAdjustment.new(commitment: @commitment, person: person(:member2))).create?
    end
  end

  # Decision 10: organizers see only their own commitments' people, and
  # only their progress.
  test "a person's commitments page shows others only what they run" do
    other = create_world_commitment("Other", team: @org, owing_team: @members)
    with_organizer_grants("Commitment Organizer > Club") do
      @commitment.commitment_organizers.create!(person: person(:organizer))

      mine = PersonCommitmentsPolicy.new(person(:member).user, person(:member))
      assert mine.show?
      assert_equal [ @commitment, other ].map(&:id).sort, mine.visible_commitments.map(&:id).sort

      organizer_view = PersonCommitmentsPolicy.new(person(:organizer).user, person(:member))
      assert organizer_view.show?
      assert_equal [ @commitment ], organizer_view.visible_commitments

      assert_not PersonCommitmentsPolicy.new(person(:organizer).user, person(:outsider)).show?
      assert_not PersonCommitmentsPolicy.new(person(:member2).user, person(:member)).show?
    end
  end

  test "sources: organizers add subjects their kind allows, and can't edit an unavailable one" do
    source = @commitment.commitment_sources.create!(kind: "checkins", subject: @outreach)
    assert CommitmentSourcePolicy.new(person(:admin).user, source).update?
    assert_not CommitmentSourcePolicy.new(person(:member).user, source).update?

    source.update_column(:kind, "gone")
    assert_not CommitmentSourcePolicy.new(person(:admin).user, source.reload).update?
    assert CommitmentSourcePolicy.new(person(:admin).user, source).destroy?
  end

  private

  def policy(name, record)
    CommitmentPolicy.new(person(name).user, record)
  end
end
