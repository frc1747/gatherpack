require "test_helper"
require "support/orders_world"
require "support/order_notices_helper"

# The recurring jobs run the reminders, and orders ships them as a
# recurring.d fragment (the seam), not in config/recurring.yml.
class Orders::JobsTest < ActiveSupport::TestCase
  include ActiveJob::TestHelper
  include OrdersWorld
  include OrderNoticesHelper

  test "the jobs are scheduled from config/recurring.d" do
    tasks = GatherPack::RecurringSchedule.tasks(env: :test)

    assert_equal %w[Orders::AutoCloseJob Orders::DigestJob Orders::ReminderJob],
      tasks.values_at(:orders_auto_close, :orders_digest, :orders_reminders).map { |task| task[:class] }.sort
    assert_includes File.read(Rails.root.join("config/recurring.yml")), "GatherPack::RecurringSchedule.yaml"
  end

  test "the digest job sends the Orders summary, and nothing with the flag off" do
    world = build_orders_world
    with_orders(world) { approved_request(world) }
    travel 2.days
    clear_enqueued_jobs

    with_orders(world, feature_orders: "false") do
      Orders::DigestJob.perform_now
      Orders::ReminderJob.perform_now
      Orders::AutoCloseJob.perform_now
      assert_empty enqueued_emails
    end

    with_orders(world) do
      Orders::DigestJob.perform_now
      assert_equal addresses(world.buyer, world.manager, world.admin), emailed
      assert_match "Ready to buy", email_to(world.buyer)
    end

    clear_enqueued_jobs
    with_orders(world, orders_notices: "each") do
      Orders::DigestJob.perform_now
      assert_empty enqueued_emails
    end
  end

  test "the reminder job reminds once however often it runs" do
    world = build_orders_world
    with_orders(world) do
      submitted_request(world, needed_by: Date.current + 3)
      clear_enqueued_jobs
      3.times { Orders::ReminderJob.perform_now }

      assert_equal addresses(world.mentor, world.manager, world.admin), emailed
    end
  end

  test "the auto-close job closes what is due" do
    world = build_orders_world
    with_orders(world, orders_close_after_days: "5") do
      request = approved_request(world)
      buy(world, request.order_lines.to_a, vendor: world.preferred_vendor)
      request.mark_all_received!(by: world.requester)
      travel 6.days do
        Orders::AutoCloseJob.perform_now
      end

      assert_predicate request.reload, :closed?
    end
  end
end
