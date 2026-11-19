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

  # The reminders as everyone hears them when they chose an email each
  # time; the other choices are tested where they matter.
  def with_notices(**overrides, &block)
    with_orders(@world, orders_notices: "each", **overrides, &block)
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

  test "someone who chose off isn't reminded as a buyer, whatever else they chose" do
    with_notices do
      with_personal_choices(@world.manager => :off, @world.admin => :daily) do
        start approved_request(@world, needed_by: Date.current + 2)
        Orders::Reminders.needed_soon

        assert_equal addresses(@world.buyer, @world.admin), emailed
      end
    end
  end

  test "what's needed soon is urgent: it goes right away under the digest choices, and not when off" do
    %w[daily weekly].each do |choice|
      with_notices(orders_notices: choice) do
        request = start(approved_request(@world, needed_by: Date.current + 2))
        Orders::Reminders.needed_soon

        assert_equal addresses(@world.buyer, @world.manager, @world.admin), emailed, choice
        request.update_columns(status: OrderRequest.statuses[:cancelled])
      end
    end

    with_notices(orders_notices: "off") do
      start approved_request(@world, needed_by: Date.current + 2)

      assert_equal 0, Orders::Reminders.needed_soon
      assert_empty emailed
    end
  end

  test "the undecided reminder goes only to those who chose an email each time" do
    with_notices(orders_notices: "daily") do
      with_personal_choices(@world.manager => :each) do
        submitted_request(@world)
        travel_to 6.days.from_now
        clear_enqueued_jobs
        Orders::Reminders.undecided

        assert_equal addresses(@world.manager), emailed
      end
    end
  end

  test "with no buyer rows, only admins hear of what's needed soon and get the digest; team managers don't" do
    with_notices(orders_buyers: "") do
      start approved_request(@world, needed_by: Date.current + 2)
      Orders::Reminders.needed_soon
      assert_equal addresses(@world.admin), emailed
    end

    with_notices(orders_buyers: "", orders_notices: "daily") do
      travel_to 2.days.from_now
      clear_enqueued_jobs
      Orders::Reminders.digest
      assert_equal addresses(@world.admin), emailed
    end
  end

  test "on a team no grant reaches, its manager and the admin are the buyers" do
    art_manager = orders_person("Artlead", teams: { @world.art => true })
    with_notices do
      start approved_request(@world, team: @world.art, by: @world.outsider, needed_by: Date.current + 2)
      Orders::Reminders.needed_soon
      assert_equal addresses(art_manager, @world.admin), emailed
    end

    with_notices(orders_notices: "daily") do
      travel_to 2.days.from_now
      clear_enqueued_jobs
      Orders::Reminders.digest
      assert_equal addresses(art_manager, @world.admin), emailed
    end
  end

  test "a reminder nobody was told of isn't marked, so a later run can send it" do
    with_notices(orders_buyers: "") do
      choices = { @world.manager => :off, @world.admin => :off }
      with_personal_choices(choices) do
        request = start(approved_request(@world, needed_by: Date.current + 2))

        assert_equal 0, Orders::Reminders.needed_soon
        assert_empty emailed
        assert_equal 0, OrderNoticeMark.where(order_request: request).count

        choices[@world.admin] = :daily
        assert_equal 1, Orders::Reminders.needed_soon
        assert_equal addresses(@world.admin), emailed
        assert_equal 1, OrderNoticeMark.where(order_request: request).count
      end
    end
  end

  test "an undecided reminder nobody could receive isn't marked either" do
    with_notices(approval_steps: [ { key: "approval", name: "Approval", minimum: 0, approvers: [] } ]) do
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

  # -- the Orders summary (Orders::Digest, Orders::Reminders.digest) -------

  def with_digest(**overrides, &block)
    with_orders(@world, orders_notices: "daily", **overrides, &block)
  end

  test "each buyer in reach gets one summary a day of what's ready to buy, and nothing goes when none wait" do
    with_digest do
      approved_request(@world, title: "Belts", needed_by: Date.current + 9)
      approved_request(@world, lines: [ { description: "Pinion", price: 8 } ], title: "Pinions")
      travel_to 2.days.from_now
      clear_enqueued_jobs

      assert_equal 3, Orders::Reminders.digest
      assert_equal addresses(@world.buyer, @world.manager, @world.admin), emailed
      body = email_to(@world.buyer)
      assert_match(/Ready to buy.*Belts.*Pinions/m, body)
      assert_match "Orders summary", enqueued_emails.first[1]

      clear_enqueued_jobs
      assert_equal 0, Orders::Reminders.digest
      assert_empty emailed

      travel_to 1.day.from_now
      assert_equal 3, Orders::Reminders.digest

      clear_enqueued_jobs
      OrderRequest.update_all(status: OrderRequest.statuses[:cancelled])
      travel_to 1.day.from_now
      assert_equal 0, Orders::Reminders.digest
      assert_empty emailed
    end
  end

  test "a digest holds only requests within the buyer's reach" do
    with_digest do
      start approved_request(@world, team: @world.art, by: @world.outsider)
      travel_to 2.days.from_now
      Orders::Reminders.digest

      assert_equal addresses(@world.admin), emailed
    end
  end

  test "a bought item is no longer in the digest" do
    with_digest do
      request = approved_request(@world)
      buy(@world, request.order_lines.to_a, vendor: @world.preferred_vendor)
      clear_enqueued_jobs
      travel_to 2.days.from_now

      assert_equal 0, Orders::Reminders.digest
      assert_empty emailed
    end
  end

  test "approvers' summary lists what waits for their approval, oldest first" do
    with_digest do
      submitted_request(@world, title: "Older")
      travel_to 1.hour.from_now
      submitted_request(@world, title: "Newer")
      travel_to 2.days.from_now
      clear_enqueued_jobs
      Orders::Reminders.digest

      assert_equal approvers, emailed
      assert_match(/Waiting for your approval.*Older.*Newer/m, email_to(@world.mentor))
      assert_match "asked by Requester Example", email_to(@world.mentor)
      assert_nil email_to(@world.parent), "a relative of the requester can't decide it"
    end
  end

  test "requesters and watchers hear what happened to their requests since the last summary" do
    with_digest do
      approved = submitted_request(@world, title: "Belts")
      approved.follow!(@world.teammate)
      sent_back = submitted_request(@world, title: "Pinions")
      ordered = approved_request(@world, title: "Motors")
      travel_to 1.day.from_now
      approved.decide!(:approved, by: @world.mentor)
      sent_back.decide!(:changes_requested, by: @world.mentor, comment: "Which size?")
      buy(@world, ordered.order_lines.to_a, vendor: @world.preferred_vendor)
      clear_enqueued_jobs
      Orders::Reminders.digest

      body = email_to(@world.requester)
      assert_match(/Your requests/, body)
      assert_match(/Belts<\/a>: approved/, body)
      assert_match(/Pinions<\/a>: changes requested/, body)
      assert_match(/Motors<\/a>: ordered/, body)
      assert_match(/Belts<\/a>: approved/, email_to(@world.teammate))
      assert_no_match(/Pinions/, email_to(@world.teammate))
    end
  end

  test "a request's line shows its newest state, and a step's approval or one's own action isn't news" do
    with_digest(**two_step_settings(@world)) do
      router = submitted_request(@world, lines: [ { description: "Router", price: 600 } ], title: "Router")
      travel_to 1.day.from_now
      router.decide!(:approved, by: @world.mentor)
      own = draft_request(@world, title: "Own")
      own.submit!(by: @world.requester)
      clear_enqueued_jobs
      Orders::Reminders.digest

      assert_nil email_to(@world.requester)

      router.decide!(:approved, by: @world.manager)
      travel_to 1.minute.from_now
      buy(@world, router.order_lines.to_a, vendor: @world.preferred_vendor)
      travel_to 1.minute.from_now
      router.mark_all_received!(by: @world.teammate)
      clear_enqueued_jobs
      Orders::Reminders.digest

      body = email_to(@world.requester)
      assert_match(/Router<\/a>: everything has arrived/, body)
      assert_equal 1, body.scan("Router</a>").size
    end
  end

  test "a summary nobody could receive doesn't take the day, so a later run can send it" do
    with_digest do
      start approved_request(@world)
      travel_to 2.days.from_now
      @world.buyer.user.update_columns(email: "")
      Orders::Reminders.digest
      assert_nil OrderSummarySend.find_by(person: @world.buyer)

      @world.buyer.user.update_columns(email: "buyer-again@example.com")
      clear_enqueued_jobs
      assert_equal 1, Orders::Reminders.digest
      assert_equal [ "buyer-again@example.com" ], emailed
    end
  end

  test "approvers of the final step find requests to approve again, and buyers their delivery problems" do
    with_digest(**two_step_settings(@world)) do
      router = submitted_request(@world, lines: [ { description: "Router", price: 600 } ], title: "Router")
      router.decide!(:approved, by: @world.mentor)
      router.decide!(:approved, by: @world.manager)
      line = router.order_lines.first
      buy(@world, [ line ], vendor: @world.preferred_vendor, prices: { line.id => 90_000 })
      belts = approved_request(@world, title: "Belts")
      buy(@world, belts.order_lines.to_a, vendor: @world.preferred_vendor)
      belt = belts.order_lines.first
      belt.record_delivery!(by: @world.requester, quantity: belt.quantity, condition: :damaged, note: "Cracked")
      travel_to 2.days.from_now
      clear_enqueued_jobs
      Orders::Reminders.digest

      assert_match(/Waiting for you to approve again.*Router/m, email_to(@world.admin))
      assert_match(/Delivery problems.*Belts<\/a>: Gear/m, email_to(@world.buyer))
      assert_no_match(/Delivery problems/, email_to(@world.admin))
    end
  end

  test "under each time or off there's no summary; under the Weekly Infodump without Summaries it comes daily" do
    %w[each off].each do |choice|
      with_digest(orders_notices: choice) do
        start approved_request(@world)
        assert_equal 0, Orders::Reminders.digest, choice
        assert_empty emailed
      end
    end

    with_digest(orders_notices: "weekly") do
      start approved_request(@world)
      travel_to 2.days.from_now
      assert_equal 3, Orders::Reminders.digest
    end
  end

  test "each person's own choice decides whether they get the summary" do
    with_digest(orders_notices: "each") do
      with_personal_choices(@world.buyer => :daily, @world.manager => :weekly, @world.admin => :off) do
        start approved_request(@world)
        Orders::Reminders.digest

        assert_equal addresses(@world.buyer, @world.manager), emailed
      end
    end
  end

  test "Orders' own summary stands down while Summaries sends the Orders section" do
    with_digest do
      start approved_request(@world)
      with_personal_choices({}, handles: true) do
        assert_equal 0, Orders::Reminders.digest
        assert_empty emailed
      end
    end
  end

  test "the Orders section for Summaries is built per person, and is nil with nothing in it" do
    with_digest do
      approved_request(@world, title: "Belts")
      with_personal_choices({}, handles: true) do
        section = Orders::Digest.section(@world.buyer, since: 1.day.ago)
        assert_equal "Orders", section.heading
        assert_match(/Ready to buy.*Belts/m, section.body)
        assert_equal Rails.application.routes.url_helpers.orders_requests_url, section.link

        assert_nil Orders::Digest.section(@world.outsider, since: 1.day.ago)
      end
    end
  end

  test "the Orders section is registered with Summaries where that seam is merged" do
    skip "Summaries isn't merged here" unless defined?(GatherPack::Digests) && GatherPack::Digests.respond_to?(:[])

    entry = GatherPack::Digests[:orders]
    assert_equal "Orders", entry.label
  end

  test "names are escaped in the summary" do
    with_digest do
      @world.requester.update!(display_name: "<b>Requester</b>")
      submitted_request(@world, title: "<i>Belts</i>")
      travel_to 1.day.from_now
      clear_enqueued_jobs
      Orders::Reminders.digest

      body = email_to(@world.mentor)
      assert_match "&lt;i&gt;Belts&lt;/i&gt;", body
      assert_match "&lt;b&gt;Requester&lt;/b&gt;", body
    end
  end

  test "the digest does nothing while Orders is off" do
    with_digest { approved_request(@world) }
    clear_enqueued_jobs
    with_orders(@world, feature_orders: "false") do
      assert_equal 0, Orders::Reminders.digest
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
