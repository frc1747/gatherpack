require "test_helper"

# Two people taking the last place at once, each on their own database
# connection. This needs committed data, so it doesn't run in a transaction
# and removes what it made afterwards.
class SignupConcurrencyTest < ActiveSupport::TestCase
  self.use_transactional_tests = false

  setup do
    @made = []
    @team = make(Team.create!(name: "Race Team", team_type: team_types(:one)))
    @people = 2.times.map do |index|
      user = make(User.create!(email: "racer#{index}@example.com", password: "Password1!"))
      person = make(Person.create!(user: user, first_name: "Racer#{index}", last_name: "Test"))
      make(Membership.create!(person: person, team: @team))
      person
    end
    @event = make(Event.create!(name: "Race Day", start_time: 1.week.from_now, event_type: event_types(:one), team: @team))
    @sheet = make(SignupSheet.create!(title: "Race Sheet", team: @team, status: :open))
    make(@sheet.signup_sheet_events.create!(event: @event))
  end

  teardown do
    sheet_ids = [ @sheet&.id ].compact
    slot_ids = SignupSlot.joins(:signup_position).where(signup_positions: { signup_sheet_id: sheet_ids }).ids
    made_ids = slot_ids + @made.map(&:id) + Signup.where(signup_slot_id: slot_ids).ids + SignupPosition.where(signup_sheet_id: sheet_ids).ids
    Signup.where(signup_slot_id: slot_ids).delete_all
    SignupSlot.where(id: slot_ids).delete_all
    @made.reverse_each { |record| record.class.where(id: record.id).delete_all }
    SignupPosition.where(signup_sheet_id: sheet_ids).delete_all
    AuditLog.where(item_id: made_ids).delete_all
  end

  test "only one of two people gets the last place" do
    position = @sheet.signup_positions.create!(name: "Cashier", capacity: 2)
    slot = position.signup_slots.first
    Signup.place!(slot: slot, person: @people.first, signed_up_by: @people.first)

    results = race(slot.id) { |slot_copy, person| Signup.place!(slot: slot_copy, person: person, signed_up_by: person) }

    assert_equal 1, results.count(:placed), results.inspect
    assert_equal [ "This slot is full" ], results.reject { |result| result == :placed }
    assert_equal 2, slot.used
  end

  test "only one of two people gets the last of an item's quantity" do
    position = @sheet.signup_positions.create!(name: "Pizza", kind: :items, unit: "pizzas", capacity: 6)
    slot = position.signup_slots.first
    Signup.place!(slot: slot, person: @people.first, signed_up_by: @people.first, quantity: 3)

    results = race(slot.id) { |slot_copy, person| Signup.place!(slot: slot_copy, person: person, signed_up_by: person, quantity: 2) }

    assert_equal 1, results.count(:placed), results.inspect
    assert_equal [ "Only 1 pizza still needed" ], results.reject { |result| result == :placed }
    assert_equal 5, slot.used
  end

  private

  def make(record)
    @made << record
    record
  end

  # Runs the block in two threads at once, each with its own connection and
  # its own copy of the slot, and returns :placed or the error for each.
  def race(slot_id)
    barrier = Concurrent::CyclicBarrier.new(2)
    threads = @people.map do |person|
      Thread.new do
        ActiveRecord::Base.connection_pool.with_connection do
          slot = SignupSlot.find(slot_id)
          barrier.wait
          yield slot, person
          :placed
        rescue ActiveRecord::RecordInvalid => error
          error.record.errors.full_messages.to_sentence
        end
      end
    end
    ActiveSupport::Dependencies.interlock.permit_concurrent_loads { threads.map(&:value) }
  end
end
