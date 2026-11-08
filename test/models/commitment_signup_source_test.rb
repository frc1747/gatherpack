require "test_helper"
require_relative "../support/signup_credit_world"

# Sign-ups as a commitment credit source (spec §4.2, "Sign-ups" row).
class CommitmentSignupSourceTest < ActiveSupport::TestCase
  include SignupCreditWorld

  setup do
    travel_to Time.zone.parse("2026-10-05 12:00")
    build_signup_credit_world
    @commitment = create_world_commitment
  end

  def progress(name)
    @commitment.progress_for(person(name))
  end

  test "active sign-ups are planned and fulfilled ones confirmed; cancelled and no-show count nothing" do
    @commitment.commitment_sources.create!(kind: "signups", subject: @sheet)
    events = %w[ One Two Three Four ].each_with_index.map { |name, i| add_sheet_event(name, "2026-10-#{10 + i} 10:00") }
    sign_up(:member, @cashier, events[0], status: :active)
    sign_up(:member, @cashier, events[1], status: :fulfilled)
    sign_up(:member, @cashier, events[2], status: :cancelled)
    sign_up(:member, @cashier, events[3], status: :no_show)

    line = progress(:member).lines.first
    assert_equal [ 1, 1 ], [ line.confirmed_quantity, line.planned_quantity ]
    assert_equal [ :planned, :confirmed ], line.records.map(&:state)
    assert_equal [ "Cashier: One", "Cashier: Two" ], line.records.map(&:label)
  end

  test "an item sign-up counts once, whatever its quantity" do
    @commitment.commitment_sources.create!(kind: "signups", subject: @sheet)
    sign_up(:member, @dish, add_sheet_event("Potluck", "2026-10-10 10:00"), status: :fulfilled)

    assert_equal [ 1 ], progress(:member).lines.first.records.map(&:quantity)
    assert_equal 1, progress(:member).confirmed
  end

  test "credit goes to the person the sign-up is on behalf of" do
    @commitment.commitment_sources.create!(kind: "signups", subject: @sheet)
    sign_up(:member, @cashier, add_sheet_event("Game", "2026-10-10 10:00"), status: :fulfilled, on_behalf_of: :kid)

    assert_equal 1, progress(:kid).confirmed
    assert_equal 0, progress(:member).confirmed
  end

  test "a check-in source listed below adds nothing for an event already credited by a sign-up" do
    @commitment.commitment_sources.create!(kind: "signups", subject: @sheet)
    @commitment.commitment_sources.create!(kind: "checkins", subject: @outreach)
    game = add_sheet_event("Game", "2026-10-03 10:00")
    other = create_world_event("Cleanup", "2026-10-04 10:00")
    sign_up(:member, @cashier, game)
    with_settings(feature_signups: "true") do
      check_in(:member, game)
      check_in(:member, other)
    end

    signups, checkins = progress(:member).lines
    assert_equal [ Commitments.event_key(game.id, person(:member).id) ], signups.records.map(&:dedupe_key)
    assert_equal [ :confirmed ], signups.records.map(&:state), "the check-in fulfilled the sign-up"
    assert_equal [ Commitments.event_key(other.id, person(:member).id) ], checkins.records.map(&:dedupe_key)
    assert_equal 2, progress(:member).confirmed
  end

  test "two people working for the same person at one event both count" do
    @commitment.update!(base_amount: 3)
    @commitment.commitment_sources.create!(kind: "signups", subject: @sheet)
    game = add_sheet_event("Game", "2026-10-10 10:00")
    sign_up(:member, @cashier, game, status: :fulfilled, on_behalf_of: :kid)
    sign_up(:kid, @cashier, game, status: :fulfilled)

    assert_equal 2, progress(:kid).confirmed
  end

  test "one person in two places at one event counts once, for the person they worked for" do
    @commitment.commitment_sources.create!(kind: "signups", subject: @sheet)
    @lead = @sheet.signup_positions.create!(name: "Shift Lead", kind: :people, capacity: 1)
    game = add_sheet_event("Game", "2026-10-10 10:00")
    sign_up(:member, @lead, game, status: :fulfilled)
    sign_up(:member, @cashier, game, status: :fulfilled, on_behalf_of: :kid)

    assert_equal 1, progress(:kid).confirmed
    assert_equal 0, progress(:member).confirmed
    everyone = @commitment.progress
    assert_equal 1, everyone[person(:kid).id].confirmed
    assert_equal 0, everyone[person(:member).id].confirmed
  end

  test "one person in two places at one event counts once for their own group" do
    @commitment.update!(group_relationship_type: @parent_of)
    @commitment.commitment_sources.create!(kind: "signups", subject: @sheet)
    @lead = @sheet.signup_positions.create!(name: "Shift Lead", kind: :people, capacity: 1)
    game = add_sheet_event("Game", "2026-10-10 10:00")
    sign_up(:organizer, @lead, game, status: :fulfilled)
    sign_up(:organizer, @cashier, game, status: :fulfilled, on_behalf_of: :kid)

    assert_equal [ "Cashier: Game" ], progress(:kid).lines.first.records.map(&:label)
    assert_equal 1, progress(:kid).confirmed
  end

  test "a worker's check-in at an event doesn't add to their place for someone else" do
    @commitment.commitment_sources.create!(kind: "signups", subject: @sheet)
    @commitment.commitment_sources.create!(kind: "checkins", subject: @outreach)
    game = add_sheet_event("Game", "2026-10-03 10:00")
    sign_up(:member, @cashier, game, on_behalf_of: :kid)
    with_settings(feature_signups: "true") { check_in(:member, game) }

    assert_equal 0, progress(:member).confirmed + progress(:member).planned
    assert_equal 1, progress(:kid).confirmed + progress(:kid).planned
  end

  test "a position source counts only that position, at its ratio" do
    @commitment.update!(base_amount: 5)
    @commitment.commitment_sources.create!(kind: "signup_positions", subject: @cashier, per: 3)
    events = (1..4).map { |i| add_sheet_event("Game #{i}", "2026-10-#{10 + i} 10:00") }
    events.each { |event| sign_up(:member, @cashier, event, status: :fulfilled) }
    sign_up(:member, @dish, events.first, status: :fulfilled)

    line = progress(:member).lines.first
    assert_equal 4, line.confirmed_quantity
    assert_equal 1, line.confirmed_credits
    assert_equal 1, line.partial
    assert_equal "Sign-ups for a position: Cashier", line.source.label
  end

  test "only events in the commitment's period, of its team or a team below it, count" do
    @commitment.commitment_sources.create!(kind: "signups", subject: @sheet)
    [ add_sheet_event("Club game", "2026-10-10 10:00"),
      add_sheet_event("Members game", "2026-10-11 10:00", team: @members),
      add_sheet_event("Too late", "2026-11-01 10:00"),
      add_sheet_event("Too early", "2026-09-30 10:00"),
      add_sheet_event("Elsewhere", "2026-10-12 10:00", team: @other_org) ].each { |event| sign_up(:member, @cashier, event) }

    assert_equal [ "Cashier: Club game", "Cashier: Members game" ], progress(:member).lines.first.records.map(&:label)
  end

  test "organizers pick from the sheets and positions they also run" do
    archived = SignupSheet.create!(title: "Old", team: @club, status: :archived, created_by: person(:organizer))
    with_settings(signups_organizers: "Commitment Organizer > Club") do
      assert_equal [ @sheet ], Commitments::SignupSource.subject_choices(@commitment, person(:organizer)).to_a
      assert_equal [ @cashier, @dish ], Commitments::SignupPositionSource.subject_choices(@commitment, person(:organizer)).to_a
      assert_includes Commitments::SignupSource.subject_choices(@commitment, person(:admin)), @sheet
      assert_not_includes Commitments::SignupSource.subject_choices(@commitment, person(:admin)), archived
    end
    assert_empty Commitments::SignupSource.subject_choices(@commitment, person(:member))
    assert_empty Commitments::SignupSource.subject_choices(@commitment, person(:organizer)), "without the grant they no longer run it"
  end

  test "organizers of a sheet can still change its sources once it's archived" do
    with_settings(signups_organizers: "Commitment Organizer > Club", commitments_organizers: "Commitment Organizer > Club") do
      @commitment.commitment_organizers.create!(person: person(:organizer))
      sheet_source = @commitment.commitment_sources.create!(kind: "signups", subject: @sheet)
      position_source = @commitment.commitment_sources.create!(kind: "signup_positions", subject: @cashier)
      @sheet.archived!

      [ sheet_source, position_source ].each do |source|
        source.reload.per = 3
        assert CommitmentSourcePolicy.new(person(:organizer).user, source).update?
        assert_not CommitmentSourcePolicy.new(person(:member).user, source).update?
      end
      assert_empty Commitments::SignupSource.subject_choices(@commitment, person(:organizer)), "archived sheets stay out of the picker"
    end
  end

  test "a manager of the sheet's team or a team above it picks from its sheets" do
    Membership.create!(person: person(:member2), team: @org, manager: true)
    assert_equal [ @sheet ], Commitments::SignupSource.subject_choices(@commitment, person(:member2)).to_a
    assert_empty Commitments::SignupSource.subject_choices(@commitment, person(:crew_manager))
  end

  test "each kind takes its own subject type" do
    assert @commitment.commitment_sources.build(kind: "signups", subject: @sheet).valid?
    assert_not @commitment.commitment_sources.build(kind: "signups", subject: @cashier).valid?
    assert @commitment.commitment_sources.build(kind: "signup_positions", subject: @cashier).valid?
    assert_not @commitment.commitment_sources.build(kind: "signup_positions", subject: @sheet).valid?
  end

  test "how to earn links the upcoming dates with a place free" do
    source = @commitment.commitment_sources.create!(kind: "signups", subject: @sheet)
    add_sheet_event("Past", "2026-10-02 10:00")
    open_game = add_sheet_event("Open", "2026-10-10 10:00")
    full = add_sheet_event("Full", "2026-10-11 10:00")
    @cashier.signup_slots.find_by!(event: full).update!(capacity: 1)
    @dish.signup_slots.find_by!(event: full).update!(disabled: true)
    sign_up(:member2, @cashier, full)

    how = source.kind_instance.how_to_earn
    assert_equal "Sign up on Snack Stand", how.text
    path = Rails.application.routes.url_helpers.signup_sheet_path(@sheet, anchor: "event_#{open_game.id}")
    assert_equal [ [ "Open, Sat Oct 10", path ] ], how.links

    @sheet.closed!
    assert_empty source.reload.kind_instance.how_to_earn.links
  end

  test "a position source's how to earn names the position" do
    source = @commitment.commitment_sources.create!(kind: "signup_positions", subject: @cashier)
    assert_equal "Sign up as Cashier on Snack Stand", source.kind_instance.how_to_earn.text
  end

  test "sources watch the sign-up notifications" do
    assert_equal %w[ signup_changed.gatherpack signup_sheet_changed.gatherpack ], Commitments::SignupPositionSource.watches
  end
end
