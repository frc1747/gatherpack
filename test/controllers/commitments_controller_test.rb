require "test_helper"
require_relative "../support/commitments_world"

class CommitmentsControllerTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers
  include ActiveJob::TestHelper
  include CommitmentsWorld

  setup do
    host! "localhost"
    build_commitments_world
    @commitment = create_world_commitment(description: "Work **two** shifts.")
    @commitment.commitment_sources.create!(kind: "checkins", subject: @outreach)
    @event = create_world_event("Outreach Day", "2026-10-12 10:00")
    check_in(:member, @event)
  end

  test "commitments are off unless the feature is on" do
    sign_in person(:admin).user
    get commitments_path
    assert_redirected_to root_path
    get commitment_path(@commitment)
    assert_redirected_to root_path
  end

  test "a grant holder creates a commitment, adds a source and an organizer" do
    BadgeAssignment.create!(badge: @organizer_badge, person: person(:member2))
    with_feature_and_grants("Commitment Organizer > Club") do
      sign_in person(:organizer).user

      get new_commitment_path
      assert_response :success

      assert_difference "Commitment.count" do
        post commitments_path, params: { commitment: commitment_params(team_id: @club.id) }
      end
      commitment = Commitment.order(:created_at).last
      assert_redirected_to edit_commitment_path(commitment, anchor: "sources")
      assert_equal [ person(:organizer) ], commitment.organizers.to_a

      get edit_commitment_path(commitment)
      assert_response :success
      get new_commitment_commitment_source_path(commitment, kind: "checkins")
      assert_response :success

      post commitment_commitment_sources_path(commitment), params: { commitment_source: { kind: "checkins", subject_id: @outreach.id, per: 3, credits: 1, max_credits: 2 } }
      assert_redirected_to edit_commitment_path(commitment, anchor: "sources")
      source = commitment.commitment_sources.sole
      assert_equal [ @outreach, 3, 2 ], [ source.subject, source.per, source.max_credits ]

      get edit_commitment_commitment_source_path(commitment, source)
      assert_response :success
      patch commitment_commitment_source_path(commitment, source), params: { commitment_source: { per: 2 } }
      assert_equal 2, source.reload.per

      post commitment_commitment_organizers_path(commitment), params: { commitment_organizer: { person_id: person(:member2).id } }
      assert_includes commitment.reload.organizers, person(:member2)
    end
  end

  test "people can't create commitments outside their reach or run ones they don't organize" do
    with_feature_and_grants("Commitment Organizer > Club") do
      sign_in person(:organizer).user
      assert_no_difference "Commitment.count" do
        post commitments_path, params: { commitment: commitment_params(team_id: @org.id) }
      end

      patch commitment_path(@commitment), params: { commitment: { title: "Renamed" } }
      post commitment_commitment_sources_path(@commitment), params: { commitment_source: { kind: "checkins", subject_id: @meeting.id } }
      assert_equal "Shifts", @commitment.reload.title
      assert_equal 1, @commitment.commitment_sources.count

      sign_in person(:member).user
      get new_commitment_path
      assert_redirected_to root_path
    end
  end

  test "an organizer sees everyone's progress, filtered, and nothing more" do
    with_feature_and_grants do
      @commitment.commitment_organizers.create!(person: person(:organizer))
      @commitment.commitment_adjustments.create!(person: person(:member2), credits: 2, reason: "Done early")
      sign_in person(:organizer).user

      get commitment_path(@commitment)
      assert_response :success
      assert_select "#progress tbody tr", 3
      assert_select "tr##{ActionView::RecordIdentifier.dom_id(person(:member), :progress)} td", text: "1"
      assert_select "a[href=?]", person_path(person(:member)), count: 0
      assert_select "tr##{ActionView::RecordIdentifier.dom_id(person(:kid), :progress)}", text: /#{Commitment::SELF_APPROVAL_REASON}/

      get commitment_path(@commitment, filter: "met")
      assert_select "#progress tbody tr", 1
      get commitment_path(@commitment, filter: "nothing_planned")
      assert_select "#progress tbody tr", 2, "not met, with nothing planned"

      get person_commitments_path(person(:member))
      assert_response :success
      get person_commitments_path(person(:outsider))
      assert_redirected_to root_path
    end
  end

  test "someone who owes sees their own progress and how to earn, not others'" do
    travel_to Time.zone.parse("2026-10-05 12:00") do
      with_feature do
        sign_in person(:member).user

        get commitments_path
        assert_response :success
        assert_select "h3", text: "Shifts"
        assert_match "1 confirmed, 0 planned, 2 shifts owed", response.body
        assert_match "Check in at any Outreach event", response.body

        get commitment_path(@commitment)
        assert_response :success
        assert_select "#progress", count: 0
        assert_no_match "MemberTwo", response.body

        get person_commitments_path(person(:member))
        assert_response :success
        get person_commitments_path(person(:member2))
        assert_redirected_to root_path

        sign_in person(:outsider).user
        get commitment_path(@commitment)
        assert_redirected_to root_path
      end
    end
  end

  test "organizers record adjustments, but not for themselves or relatives" do
    with_feature_and_grants do
      @commitment.commitment_organizers.create!(person: person(:organizer))
      sign_in person(:organizer).user

      get new_commitment_commitment_adjustment_path(@commitment, person_id: person(:member).id)
      assert_response :success
      assert_select "option", text: "Kid World", count: 0

      post commitment_commitment_adjustments_path(@commitment), params: { commitment_adjustment: { person_id: person(:member).id, credits: 1, reason: "Ran the raffle" } }
      assert_redirected_to commitment_path(@commitment)
      adjustment = @commitment.commitment_adjustments.sole
      assert_equal person(:organizer), adjustment.created_by
      assert @commitment.progress_for(person(:member)).met?

      assert_no_difference "CommitmentAdjustment.count" do
        post commitment_commitment_adjustments_path(@commitment), params: { commitment_adjustment: { person_id: person(:kid).id, credits: 2, reason: "Mine" } }
        post commitment_commitment_adjustments_path(@commitment), params: { commitment_adjustment: { person_id: person(:outsider).id, credits: 2, reason: "Not owed" } }
      end

      delete commitment_commitment_adjustment_path(@commitment, adjustment)
      assert_redirected_to commitment_path(@commitment)
      assert_empty @commitment.commitment_adjustments.reload
    end
  end

  test "message people with open commitments, one email each" do
    with_feature do
      sign_in person(:admin).user
      @commitment.commitment_adjustments.create!(person: person(:member2), credits: 2, reason: "Done early")

      assert_enqueued_jobs 2, only: SendEmailJob do
        post message_commitment_path(@commitment), params: { subject: "Shifts", body: "Please sign up." }
      end
      assert_redirected_to commitment_path(@commitment)

      sign_in person(:member).user
      assert_no_enqueued_jobs only: SendEmailJob do
        post message_commitment_path(@commitment), params: { subject: "Spam", body: "Hi" }
      end
    end
  end

  test "an unavailable source shows as not counted and can be removed" do
    with_feature do
      source = @commitment.commitment_sources.sole
      source.update_column(:kind, "gone")
      sign_in person(:admin).user

      get commitment_path(@commitment)
      assert_response :success
      assert_match "Gone (unavailable)", response.body
      get edit_commitment_path(@commitment)
      assert_response :success

      delete commitment_commitment_source_path(@commitment, source)
      assert_empty @commitment.commitment_sources.reload
    end
  end

  test "the last organizer can't be removed, and a commitment can be deleted" do
    with_feature do
      commitment = create_world_commitment("Mine", created_by: person(:admin))
      sign_in person(:admin).user

      delete commitment_commitment_organizer_path(commitment, commitment.commitment_organizers.sole)
      assert_equal 1, commitment.commitment_organizers.count

      assert_difference "Commitment.count", -1 do
        delete commitment_path(commitment)
      end
      assert_redirected_to commitments_path
    end
  end

  private

  def commitment_params(**overrides)
    { title: "Outreach", owing_team_id: @club.id, base_amount: 3, unit: "events", counts_when: "confirmed",
      starts_on: "2026-09-01", ends_on: "2027-05-31" }.merge(overrides)
  end
end
