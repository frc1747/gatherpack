require "test_helper"
require_relative "../support/commitments_world"

class CommitmentsDuplicatorTest < ActiveSupport::TestCase
  include CommitmentsWorld

  setup do
    build_commitments_world
    @badge = @organizer_badge
    BadgeAssignment.create!(badge: @badge, person: person(:member))
    @commitment = create_world_commitment(description: "Twice a month", owing_badge: @badge, counts_when: :planned)
    with_organizer_grants("Commitment Organizer > Club") { @commitment.commitment_organizers.create!(person: person(:organizer)) }
    @first = @commitment.commitment_sources.create!(kind: "checkins", subject: @outreach, credits: 2, position: 1)
    @second = @commitment.commitment_sources.create!(kind: "checkins", subject: @meeting, max_credits: 4, position: 2)
    @commitment.commitment_adjustments.create!(person: person(:member), credits: 1, reason: "Helped", created_by: person(:admin))
  end

  test "copies the fields, badges, organizers and sources in order, but not adjustments" do
    copy = nil
    assert_difference -> { Commitment.count } => 1, -> { CommitmentSource.count } => 2 do
      copy = Commitments::Duplicator.new(@commitment, created_by: person(:crew_manager)).duplicate
    end

    assert copy.persisted?
    assert_equal "Shifts (copy)", copy.title
    assert_equal [ @commitment.team, @commitment.owing_team, @badge, "Twice a month", 2, "shifts", "planned" ],
      [ copy.team, copy.owing_team, copy.owing_badge, copy.description, copy.base_amount, copy.unit, copy.counts_when ]
    assert_equal [ @commitment.starts_on, @commitment.ends_on ], [ copy.starts_on, copy.ends_on ]
    assert_equal person(:crew_manager), copy.created_by
    assert_equal [ [ "checkins", @outreach, 2, nil ], [ "checkins", @meeting, 1, 4 ] ],
      copy.commitment_sources.map { |source| [ source.kind, source.subject, source.credits, source.max_credits ] }
    assert_equal [ person(:organizer), person(:crew_manager) ].map(&:id).sort, copy.commitment_organizers.map(&:person_id).sort
    assert_empty copy.commitment_adjustments
    assert_equal 1, @commitment.reload.commitment_adjustments.count
    assert_equal "Shifts", @commitment.title
  end

  test "makes nothing when a part can't be copied" do
    CommitmentSource.define_singleton_method(:new) { |*| raise ActiveRecord::RecordNotSaved, "boom" }
    assert_no_difference [ "Commitment.count", "CommitmentOrganizer.count" ] do
      assert_raises(ActiveRecord::RecordNotSaved) { Commitments::Duplicator.new(@commitment, created_by: person(:admin)).duplicate }
    end
  ensure
    CommitmentSource.singleton_class.remove_method(:new)
  end
end
