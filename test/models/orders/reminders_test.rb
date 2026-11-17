require "test_helper"
require "support/orders_world"
require "support/order_notices_helper"

# The scheduled notices and the auto-close (spec §3.11).
class Orders::RemindersTest < ActiveSupport::TestCase
  include ActiveJob::TestHelper
  include OrdersWorld
  include OrderNoticesHelper

  setup do
    travel_to Time.zone.parse("2026-11-16 09:00")
    @world = build_orders_world
  end

  def with_notices(**overrides, &block)
    with_orders(@world, **overrides, &block)
  end

  def start(request)
    clear_enqueued_jobs
    request
  end

  def approvers
    addresses(@world.mentor, @world.manager, @world.admin)
  end

  # -- needed soon ------------------------------------------------------------

  test "an undecided request needed in 3 days reminds its approvers, once" do
    with_notices do
      start submitted_request(@world, needed_by: Date.current + 3)

      assert_equal 1, Orders::Reminders.needed_soon
      assert_equal approvers, emailed
      assert_match "Needed soon", enqueued_emails.first[1]

      clear_enqueued_jobs
      assert_equal 0, Orders::Reminders.needed_soon
      travel_to 1.day.from_now
      Orders::Reminders.needed_soon
      assert_empty emailed
    end
  end

  test "an approved request nothing is ordered for reminds its buyers, not its approvers" do
    with_notices do
      start approved_request(@world, needed_by: Date.current + 2)
      Orders::Reminders.needed_soon

      assert_equal addresses(@world.buyer, @world.manager, @world.admin), emailed
    end
  end

  test "someone who chose no buying notices isn't reminded as a buyer, whatever else they chose" do
    with_notices do
      OrderNoticePreference.create!(person: @world.manager, buyer_notices: :off)
      OrderNoticePreference.create!(person: @world.admin, buyer_notices: :immediate)
      start approved_request(@world, needed_by: Date.current + 2)
      Orders::Reminders.needed_soon

      assert_equal addresses(@world.buyer, @world.admin), emailed
    end
  end

  test "with no buyer grants, an admin and a team manager hear of what's needed soon and get the digest" do
    with_notices(orders_buyers: "") do
      start approved_request(@world, needed_by: Date.current + 2)
      Orders::Reminders.needed_soon
      assert_equal addresses(@world.manager, @world.admin), emailed

      clear_enqueued_jobs
      Orders::Reminders.buyer_digest
      assert_equal addresses(@world.manager, @world.admin), emailed
    end
  end

  test "on a team no grant reaches, its manager and the admin are the buyers" do
    with_notices do
      art_manager = orders_person("Artlead", teams: { @world.art => true })
      start approved_request(@world, team: @world.art, by: @world.outsider, needed_by: Date.current + 2)
      Orders::Reminders.needed_soon
      assert_equal addresses(art_manager, @world.admin), emailed

      clear_enqueued_jobs
      Orders::Reminders.buyer_digest
      assert_equal addresses(art_manager, @world.admin), emailed
    end
  end

  test "a reminder nobody was told of isn't marked, so a later run can send it" do
    with_notices(orders_buyers: "") do
      OrderNoticePreference.create!(person: @world.manager, buyer_notices: :off)
      OrderNoticePreference.create!(person: @world.admin, buyer_notices: :off)
      request = start(approved_request(@world, needed_by: Date.current + 2))

      assert_equal 0, Orders::Reminders.needed_soon
      assert_empty emailed
      assert_equal 0, OrderNoticeMark.where(order_request: request).count

      OrderNoticePreference.find_by(person: @world.admin).update!(buyer_notices: :digest)
      assert_equal 1, Orders::Reminders.needed_soon
      assert_equal addresses(@world.admin), emailed
      assert_equal 1, OrderNoticeMark.where(order_request: request).count
    end
  end

  test "an undecided reminder nobody could receive isn't marked either" do
    with_notices(orders_approval_steps: JSON.generate([ { "key" => "approval", "name" => "Approval", "minimum" => 0, "approvers" => [] } ])) do
      @world.admin.user.update_columns(email: " ")
      @world.manager.user.update_columns(email: "  ")
      request = submitted_request(@world)
      travel_to 6.days.from_now

      assert_equal 0, Orders::Reminders.undecided
      assert_equal 0, OrderNoticeMark.where(order_request: request).count
    end
  end

  test "approvers reminded while it was undecided, the buyers are reminded once it's approved" do
    with_notices do
      request = start(submitted_request(@world, needed_by: Date.current + 2))
      Orders::Reminders.needed_soon
      assert_equal approvers, emailed

      request.decide!(:approved, by: @world.mentor)
      clear_enqueued_jobs
      Orders::Reminders.needed_soon
      assert_equal addresses(@world.buyer, @world.manager, @world.admin), emailed

      clear_enqueued_jobs
      Orders::Reminders.needed_soon
      assert_empty emailed
    end
  end

  test "a request needed later, already ordered, or without a date isn't reminded" do
    with_notices do
      submitted_request(@world, needed_by: Date.current + 4)
      submitted_request(@world)
      ordered = approved_request(@world, needed_by: Date.current + 1)
      buy(@world, ordered.order_lines.to_a, vendor: @world.preferred_vendor)
      draft_request(@world, needed_by: Date.current + 1)
      clear_enqueued_jobs
      Orders::Reminders.needed_soon

      assert_empty emailed
    end
  end

  test "a new needed-by date can be reminded again" do
    with_notices do
      request = submitted_request(@world, needed_by: Date.current + 3)
      Orders::Reminders.needed_soon
      clear_enqueued_jobs
      request.edit!({ needed_by: Date.current + 2 }, by: @world.requester)
      clear_enqueued_jobs
      Orders::Reminders.needed_soon

      assert_equal approvers, emailed
    end
  end

  test "the needed-soon reminder does nothing while Orders is off" do
    request = nil
    with_notices { request = submitted_request(@world, needed_by: Date.current + 3) }
    clear_enqueued_jobs
    with_orders(@world, feature_orders: "false") do
      assert_equal 0, Orders::Reminders.needed_soon
      assert_empty emailed
      assert_equal 0, OrderNoticeMark.where(order_request: request).count
    end
  end

  # -- undecided --------------------------------------------------------------

  test "a request undecided for 5 days reminds the approvers on its current step, once" do
    with_notices(**two_step_settings(@world)) do
      request = submitted_request(@world, lines: [ { description: "Router", price: 600 } ])
      request.decide!(:approved, by: @world.mentor)
      clear_enqueued_jobs

      travel_to 4.days.from_now
      assert_equal 0, Orders::Reminders.undecided

      travel_to 2.days.from_now
      assert_equal 1, Orders::Reminders.undecided
      assert_equal addresses(@world.manager, @world.admin), emailed
      assert_match "Still waiting", enqueued_emails.first[1]

      clear_enqueued_jobs
      travel_to 3.days.from_now
      assert_equal 0, Orders::Reminders.undecided
      assert_empty emailed
    end
  end

  test "a request is reminded again when it's resubmitted and sits another 5 days" do
    with_notices do
      request = submitted_request(@world)
      travel_to 5.days.from_now
      Orders::Reminders.undecided
      request.decide!(:changes_requested, by: @world.mentor, comment: "Which size?")
      request.resubmit!(by: @world.requester)
      clear_enqueued_jobs

      assert_equal 0, Orders::Reminders.undecided
      travel_to 5.days.from_now
      assert_equal 1, Orders::Reminders.undecided
      assert_equal approvers, emailed
    end
  end

  test "approved, declined and sent-back requests aren't reminded as undecided" do
    with_notices do
      approved_request(@world)
      declined = submitted_request(@world)
      declined.decide!(:declined, by: @world.mentor, comment: "No")
      sent_back = submitted_request(@world)
      sent_back.decide!(:changes_requested, by: @world.mentor, comment: "Why")
      travel_to 6.days.from_now
      clear_enqueued_jobs

      assert_equal 0, Orders::Reminders.undecided
      assert_empty emailed
    end
  end

  test "the undecided reminder does nothing while Orders is off" do
    with_notices { submitted_request(@world) }
    travel_to 6.days.from_now
    clear_enqueued_jobs
    with_orders(@world, feature_orders: "false") do
      assert_equal 0, Orders::Reminders.undecided
      assert_empty emailed
    end
  end

  # -- buyers' digest ---------------------------------------------------------

  test "each buyer in reach gets one digest a day of what's waiting to be bought" do
    with_notices do
      OrderNoticePreference.create!(person: @world.manager, buyer_notices: :digest)
      OrderNoticePreference.create!(person: @world.admin, buyer_notices: :digest)
      approved_request(@world, title: "Belts", needed_by: Date.current + 9)
      approved_request(@world, lines: [ { description: "Pinion", price: 8 } ], title: "Pinions")
      start submitted_request(@world)

      assert_equal 3, Orders::Reminders.buyer_digest
      assert_equal addresses(@world.buyer, @world.manager, @world.admin), emailed
      body = email_to(@world.buyer)
      assert_match(/Belts.*Pinions/m, body)
      assert_no_match(/Gear/, body)
      assert_match "To buy: 2 requests", enqueued_emails.first[1]

      clear_enqueued_jobs
      assert_equal 0, Orders::Reminders.buyer_digest
      assert_empty emailed

      travel_to 1.day.from_now
      assert_equal 3, Orders::Reminders.buyer_digest
    end
  end

  test "a buyer who chose each approval or none gets no digest" do
    with_notices do
      OrderNoticePreference.create!(person: @world.buyer, buyer_notices: :immediate)
      OrderNoticePreference.create!(person: @world.manager, buyer_notices: :off)
      OrderNoticePreference.create!(person: @world.admin, buyer_notices: :digest)
      start approved_request(@world)
      Orders::Reminders.buyer_digest

      assert_equal addresses(@world.admin), emailed
    end
  end

  test "a digest holds only requests within the buyer's reach, and nothing goes when none wait" do
    with_notices do
      OrderNoticePreference.create!(person: @world.admin, buyer_notices: :digest)
      start approved_request(@world, team: @world.art, by: @world.outsider)
      Orders::Reminders.buyer_digest

      assert_equal addresses(@world.admin), emailed

      clear_enqueued_jobs
      OrderRequest.update_all(status: OrderRequest.statuses[:cancelled])
      travel_to 1.day.from_now
      assert_equal 0, Orders::Reminders.buyer_digest
      assert_empty emailed
    end
  end

  test "a bought item is no longer in the digest" do
    with_notices do
      request = approved_request(@world)
      buy(@world, request.order_lines.to_a, vendor: @world.preferred_vendor)
      clear_enqueued_jobs

      assert_equal 0, Orders::Reminders.buyer_digest
      assert_empty emailed
    end
  end

  test "the digest does nothing while Orders is off" do
    with_notices { approved_request(@world) }
    clear_enqueued_jobs
    with_orders(@world, feature_orders: "false") do
      assert_equal 0, Orders::Reminders.buyer_digest
      assert_empty emailed
    end
  end

  test "the undecided reminder names the date in the app's time zone" do
    with_notices(time_zone: "America/Chicago") do
      travel_to Time.utc(2026, 11, 17, 1, 0) # Monday 7 pm in Chicago
      submitted_request(@world)
      travel_to 5.days.from_now
      clear_enqueued_jobs
      Orders::Reminders.undecided

      assert_match "since Mon Nov 16", email_to(@world.mentor)
    end
  end

  # -- auto-close -------------------------------------------------------------

  def received_request
    request = approved_request(@world)
    buy(@world, request.order_lines.to_a, vendor: @world.preferred_vendor)
    request.mark_all_received!(by: @world.requester)
    request.reload
  end

  test "a received request closes after orders_close_after_days" do
    with_notices(orders_close_after_days: "10") do
      request = received_request
      travel_to 9.days.from_now
      assert_equal 0, Orders::Reminders.auto_close
      assert_predicate request.reload, :received?

      travel_to 2.days.from_now
      assert_equal 1, Orders::Reminders.auto_close
      assert_predicate request.reload, :closed?
      assert_nil request.events.last.actor
      assert_equal "closed", request.events.last.action
    end
  end

  test "requests that aren't received are never auto-closed" do
    with_notices(orders_close_after_days: "1") do
      ordering = approved_request(@world)
      buy(@world, ordering.order_lines.to_a, vendor: @world.preferred_vendor)
      submitted = submitted_request(@world)
      travel_to 30.days.from_now

      assert_equal 0, Orders::Reminders.auto_close
      assert_predicate ordering.reload, :ordering?
      assert_predicate submitted.reload, :submitted?
    end
  end

  test "nothing closes while Orders is off" do
    request = nil
    with_notices(orders_close_after_days: "1") { request = received_request }
    travel_to 30.days.from_now
    with_orders(@world, feature_orders: "false") do
      assert_equal 0, Orders::Reminders.auto_close
      assert_predicate request.reload, :received?
    end
  end
end
