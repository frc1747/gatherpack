require "test_helper"
require_relative "../support/commitments_world"

class CommitmentProgressTest < ActiveSupport::TestCase
  include CommitmentsWorld

  # A kind whose records the test sets directly, standing in for a kind from
  # another branch (sign-ups): planned and confirmed records keyed by event.
  class ListedSource < Commitments::SourceKind
    cattr_accessor :list, default: []

    def self.label
      "Listed"
    end

    def self.subject_type
      "EventType"
    end

    def self.subject_choices(_commitment, _person)
      EventType.all
    end

    def records(person_ids)
      list.select { |record| person_ids.include?(record.person_id) }
    end

    def how_to_earn
      Commitments::HowToEarn.new(text: "Be listed", links: [])
    end
  end

  # After the period, so every check-in in it is at an event that has
  # started (confirmed).
  setup do
    travel_to Time.zone.parse("2026-11-15 12:00")
    build_commitments_world
    Commitments.register_source(:listed, ListedSource)
    ListedSource.list = []
    @commitment = create_world_commitment
    @games = (1..4).map { |day| create_world_event("Outreach #{day}", "2026-10-#{day + 10} 10:00") }
  end

  teardown do
    Commitments.unregister_source(:listed)
  end

  test "check-ins at the source's event type count, on the team or below, within the period" do
    @commitment.commitment_sources.create!(kind: "checkins", subject: @outreach)
    check_in(:member, @games[0])
    check_in(:member, create_world_event("Below", "2026-10-20 10:00", team: @members))
    check_in(:member, create_world_event("Wrong type", "2026-10-20 10:00", event_type: @meeting))
    check_in(:member, create_world_event("Other team", "2026-10-20 10:00", team: @other_org))
    check_in(:member, create_world_event("Too late", "2026-11-01 10:00"))
    check_in(:member, create_world_event("Last day", "2026-10-31 22:00"))

    progress = @commitment.progress_for(person(:member))
    assert_equal [ "Checked in: Outreach 1", "Checked in: Below", "Checked in: Last day" ], progress.lines.first.records.map(&:label)
    assert_equal 3, progress.confirmed
    assert_equal 0, progress.planned
    assert_equal 0, progress.remaining
    assert progress.met?
  end

  test "ratio: 3 check-ins earn 1, with progress toward the next" do
    source = @commitment.commitment_sources.create!(kind: "checkins", subject: @outreach, per: 3, credits: 1)
    @games.first(2).each { |event| check_in(:member, event) }

    line = @commitment.progress_for(person(:member)).lines.first
    assert_equal 0, line.confirmed_credits
    assert_equal 2, line.partial

    check_in(:member, @games[2])
    line = @commitment.progress_for(person(:member)).lines.first
    assert_equal 1, line.confirmed_credits
    assert_equal 0, line.partial

    check_in(:member, @games[3])
    line = @commitment.progress_for(person(:member)).lines.first
    assert_equal 1, line.confirmed_credits
    assert_equal 1, line.partial

    assert_equal 2, source.credit_for(7)
    source.update!(per: 2, credits: 3)
    assert_equal 4, source.credit_for(3), "floor(3 × 3 / 2)"
  end

  test "cap: a source credits at most max_credits per person; adjustments aren't capped" do
    @commitment.update!(base_amount: 5)
    @commitment.commitment_sources.create!(kind: "checkins", subject: @outreach, max_credits: 2)
    @games.each { |event| check_in(:member, event) }
    @commitment.commitment_adjustments.create!(person: person(:member), credits: 2, reason: "Ran the raffle")

    progress = @commitment.progress_for(person(:member))
    line = progress.lines.first
    assert_equal 2, line.confirmed_credits
    assert line.capped
    assert_equal 0, line.partial
    assert_equal 4, progress.confirmed
    assert_equal 1, progress.remaining
  end

  test "dedupe: the first source in order credits an event, the later one adds nothing" do
    ListedSource.list = [
      record(:member, @games[0], :planned),
      record(:member, @games[1], :confirmed)
    ]
    @commitment.commitment_sources.create!(kind: "listed", subject: @outreach, position: 1)
    checkins = @commitment.commitment_sources.create!(kind: "checkins", subject: @outreach, position: 2)
    check_in(:member, @games[0])
    check_in(:member, @games[1])
    check_in(:member, @games[2])

    listed_line, checkin_line = @commitment.progress_for(person(:member)).lines
    assert_equal 1, listed_line.confirmed_credits
    assert_equal 1, listed_line.planned_credits
    assert_equal [ "Checked in: Outreach 3" ], checkin_line.records.map(&:label)

    checkins.update!(position: 0)
    checkin_line, listed_line = @commitment.reload.progress_for(person(:member)).lines
    assert_equal 3, checkin_line.confirmed_credits
    assert_equal 0, listed_line.confirmed_credits + listed_line.planned_credits
  end

  test "dedupe is per person: two people at one event both get credit" do
    @commitment.commitment_sources.create!(kind: "checkins", subject: @outreach)
    @commitment.commitment_sources.create!(kind: "checkins", subject: @outreach)
    check_in(:member, @games[0])
    check_in(:member2, @games[0])

    progress = @commitment.progress
    assert_equal 1, progress[person(:member).id].confirmed
    assert_equal 1, progress[person(:member2).id].confirmed
  end

  test "dedupe is per worker: two people working for one person at one event both count" do
    ListedSource.list = [ record(:member, @games[0], :confirmed, worker: :member), record(:member, @games[0], :confirmed, worker: :member2) ]
    @commitment.commitment_sources.create!(kind: "listed", subject: @outreach, position: 1)
    @commitment.commitment_sources.create!(kind: "checkins", subject: @outreach, position: 2)
    check_in(:member, @games[0])

    listed_line, checkin_line = @commitment.progress_for(person(:member)).lines
    assert_equal 2, listed_line.confirmed_credits
    assert_empty checkin_line.records
  end

  test "counts when: planned credit completes only when the commitment says so" do
    ListedSource.list = [ record(:member, @games[0], :confirmed), record(:member, @games[1], :planned) ]
    @commitment.commitment_sources.create!(kind: "listed", subject: @outreach)

    progress = @commitment.progress_for(person(:member))
    assert_equal 1, progress.confirmed
    assert_equal 1, progress.planned
    assert_equal 1, progress.remaining
    assert_not progress.met?

    @commitment.update!(counts_when: :planned)
    progress = @commitment.progress_for(person(:member))
    assert_equal 0, progress.remaining
    assert progress.met?
  end

  test "an unregistered kind shows as unavailable and counts nothing" do
    ListedSource.list = [ record(:member, @games[0], :confirmed) ]
    source = @commitment.commitment_sources.create!(kind: "listed", subject: @outreach)
    Commitments.unregister_source(:listed)

    progress = @commitment.reload.progress_for(person(:member))
    assert_not progress.lines.first.available?
    assert_equal 0, progress.confirmed
    assert_equal "Listed (unavailable)", source.reload.label
    assert source.valid?, "an existing source stays valid"
    assert_not @commitment.commitment_sources.build(kind: "listed", subject: @outreach).valid?
  end

  test "people who don't owe get no progress, and filters see met and nothing planned" do
    @commitment.commitment_sources.create!(kind: "checkins", subject: @outreach)
    check_in(:outsider, @games[0])
    2.times { |i| check_in(:member, @games[i]) }

    progress = @commitment.progress
    assert_equal [ person(:member), person(:member2), person(:kid) ].map(&:id).sort, progress.keys.sort
    assert progress[person(:member).id].met?
    assert progress[person(:member2).id].nothing_planned?
    assert_not progress[person(:member).id].nothing_planned?
  end

  private

  def record(name, event, state, worker: name)
    Commitments::CreditRecord.new(person_id: person(name).id, quantity: 1, state: state, date: event.start_time.to_date,
      dedupe_key: Commitments.event_key(event.id, person(worker).id), label: "Listed: #{event.name}", link: event)
  end
end
