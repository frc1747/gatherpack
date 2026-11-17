require "test_helper"

# Recording takes real row locks, so this runs outside the usual test
# transaction: each thread gets its own database connection, as concurrent
# web requests do, and the test cleans up what it made.
class StockMovementLockTest < ActiveSupport::TestCase
  self.use_transactional_tests = false

  setup do
    @team = Team.create!(name: "Lock test #{SecureRandom.hex(3)}", team_type: TeamType.first || TeamType.create!(name: "Group"))
    user = User.create!(email: "lock-#{SecureRandom.hex(4)}@example.com", password: "password123", admin: true)
    @person = Person.create!(first_name: "Lock", last_name: "Example", display_name: "Lock Example", user: user)
    @bin = Location.create!(team: @team, name: "Bin")
    @item = Item.create!(team: @team, name: "Screw", home_location: @bin)
    record(:added, 10, reason: "Starting count")
  end

  teardown do
    movements = StockMovement.where(item_id: @item.id)
    movements.where.not(reverses_id: nil).delete_all
    movements.delete_all
    StockLevel.where(item_id: @item.id).delete_all
    @item.delete
    @bin.delete
    user = @person.user
    @person.delete
    user.delete
    @team.delete
  end

  def record(kind, quantity, **options)
    StockMovement.record!(kind: kind, item: @item, location: @bin, quantity: quantity, person: @person, **options)
  end

  def level
    StockLevel.find_by(item_id: @item.id, location_id: @bin.id).quantity
  end

  # Runs the block on its own connection in a new thread.
  def in_thread(&block)
    Thread.new { ActiveRecord::Base.connection_pool.with_connection(&block) }
  end

  test "a count waits for a used in progress and works its difference out from the stock after it" do
    used_written = Queue.new
    release = Queue.new
    holder = in_thread do
      StockMovement.transaction do
        record(:used, 2)
        used_written << true
        release.pop # keeps the locks until the count has started waiting
      end
    end
    used_written.pop

    counter = in_thread { record(:counted, 8) }
    sleep 0.3
    assert counter.alive?, "the count waits for the locks"

    release << true
    holder.join
    count = counter.value

    assert_equal 0, count.quantity, "8 seen against the 8 left after the used"
    assert_equal 8, level
  end

  test "two counts and a used at the same moment all land" do
    start = Queue.new
    threads = [ -> { record(:counted, 8) }, -> { record(:used, 2) }, -> { record(:counted, 8) } ].map do |job|
      in_thread do
        start.pop
        job.call
      end
    end
    3.times { start << true }
    threads.each(&:join)

    assert_equal 4, StockMovement.where(item_id: @item.id).count
    assert_equal StockMovement.where(item_id: @item.id).sum(:quantity), level
  end

  test "two undos at once write one reversal" do
    used = record(:used, 3)
    start = Queue.new
    threads = 2.times.map do
      in_thread do
        start.pop
        StockMovement.find(used.id).undo!(by: @person)
      rescue Inventory::Refused
        :refused
      end
    end
    2.times { start << true }
    results = threads.map(&:value)

    assert_equal 1, results.count(:refused)
    assert_equal 1, StockMovement.where(reverses_id: used.id).count
    assert_equal 10, level
  end
end
