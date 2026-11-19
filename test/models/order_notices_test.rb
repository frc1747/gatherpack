require "test_helper"
require "support/orders_world"
require "support/order_notices_helper"

# Who hears about each change to an order request (spec §3.11).
class OrderNoticesTest < ActiveSupport::TestCase
  include ActiveJob::TestHelper
  include OrdersWorld
  include OrderNoticesHelper

  setup do
    @world = build_orders_world
    @requester = @world.requester
  end

  # Who hears each notice when everyone hears as things happen; the other
  # choices are tested below.
  def with_notices(**overrides, &block)
    with_orders(@world, orders_notices: "each", **overrides, &block)
  end

  def start(request = nil)
    request ||= submitted_request(@world, lines: [ { description: "Gear", price: 10 } ])
    clear_enqueued_jobs
    request
  end

  # Approvers on the one step: the mentor's badge, the robotics manager and
  # the admin. The requester's relative has the badge but can't decide.
  def approvers
    addresses(@world.mentor, @world.manager, @world.admin)
  end

  test "a submitted request goes to the approvers on its step, and no one else" do
    with_notices do
      draft = draft_request(@world)
      clear_enqueued_jobs
      draft.submit!(by: @requester)

      assert_equal approvers, emailed
      assert_match "To approve: Gear", enqueued_emails.first[1]
      assert_match "Gear", enqueued_emails.first[2]
    end
  end

  test "a resubmitted request goes to the approvers on the step it waits at" do
    with_notices do
      request = start
      request.decide!(:changes_requested, by: @world.mentor, comment: "Which size?")
      clear_enqueued_jobs
      request.resubmit!(by: @requester, comment: "The big one")

      assert_equal approvers, emailed
    end
  end

  test "an approval on a step that isn't final goes to the next step's approvers, not the one who approved" do
    with_notices(**two_step_settings(@world)) do
      request = start(submitted_request(@world, lines: [ { description: "Router", price: 600 } ]))
      request.decide!(:approved, by: @world.mentor)

      assert_equal addresses(@world.manager, @world.admin), emailed
      assert_match "Mentor Example approved", email_to(@world.admin)
      assert_empty enqueued_emails.select { |address, *| address == @requester.user.email }
    end
  end

  test "the final approval goes to the requester, the watchers and the buyers in reach" do
    with_notices do
      request = start
      request.follow!(@world.teammate)
      clear_enqueued_jobs
      request.decide!(:approved, by: @world.mentor)

      assert_equal addresses(@requester, @world.teammate, @world.buyer, @world.manager, @world.admin), emailed
      assert_match "was approved. A buyer will order it", email_to(@requester)
      assert_match "ready to buy", email_to(@world.buyer)
    end
  end

  test "a buyer who chose an email each time hears of each approval, and buyers who chose otherwise don't" do
    with_notices(orders_notices: "daily") do
      with_personal_choices(@world.buyer => :each, @world.manager => :off, @world.admin => :weekly) do
        request = start
        request.decide!(:approved, by: @world.mentor)

        assert_equal addresses(@world.buyer), emailed
        assert_match "ready to buy", email_to(@world.buyer)
      end
    end
  end

  test "a buyer outside the team's reach isn't told" do
    with_notices do
      request = start(submitted_request(@world, team: @world.art, by: @world.outsider))
      request.decide!(:approved, by: @world.admin)

      assert_equal addresses(@world.outsider), emailed
    end
  end

  test "changes requested and declined go to the requester and watchers with the comment" do
    with_notices do
      request = start
      request.follow!(@world.teammate)
      clear_enqueued_jobs
      request.decide!(:changes_requested, by: @world.mentor, comment: "Which size?")

      assert_equal addresses(@requester, @world.teammate), emailed
      assert_match "Which size?", email_to(@requester)

      request.resubmit!(by: @requester)
      clear_enqueued_jobs
      request.decide!(:declined, by: @world.mentor, comment: "Not this term")

      assert_equal addresses(@requester, @world.teammate), emailed
      assert_match "Not this term", email_to(@requester)
    end
  end

  test "ordering sends one notice for each purchase, however many items it holds" do
    with_notices do
      request = start(approved_request(@world, lines: [ { description: "Gear", price: 10 }, { description: "Belt", price: 5 } ]))
      request.follow!(@world.teammate)
      clear_enqueued_jobs
      buy(@world, request.order_lines.to_a, vendor: @world.preferred_vendor, expected_on: Date.new(2026, 12, 4))

      assert_equal addresses(@requester, @world.teammate), emailed
      assert_match "Gear and Belt were ordered from Parts Depot, expected Fri Dec 4", email_to(@requester)
    end
  end

  test "two purchases of one request each send a notice" do
    with_notices do
      request = start(approved_request(@world, lines: [ { description: "Gear", price: 10 }, { description: "Belt", price: 5 } ]))
      clear_enqueued_jobs
      buy(@world, [ request.order_lines.first ], vendor: @world.preferred_vendor)
      buy(@world, [ request.order_lines.last ], vendor: @world.preferred_vendor)

      assert_equal addresses(@requester, @requester), emailed
    end
  end

  test "a delayed item tells the requester and watchers, with the expected date" do
    with_notices do
      request = start(approved_request(@world))
      buy(@world, request.order_lines.to_a, vendor: @world.preferred_vendor)
      clear_enqueued_jobs
      request.order_lines.first.backorder!(by: @world.buyer, expected_on: Date.new(2026, 12, 18))

      assert_equal addresses(@requester), emailed
      assert_match "is delayed, expected Fri Dec 18", email_to(@requester)
    end
  end

  test "receiving everything tells the requester, watchers and the buyer" do
    with_notices do
      request = start(approved_request(@world, lines: [ { description: "Gear", price: 10 }, { description: "Belt", price: 5 } ]))
      request.follow!(@world.teammate)
      buy(@world, request.order_lines.to_a, vendor: @world.preferred_vendor)
      clear_enqueued_jobs
      request.order_lines.first.record_delivery!(by: @requester, quantity: request.order_lines.first.quantity)

      assert_empty emailed, "one of two items isn't everything"

      request.order_lines.last.record_delivery!(by: @world.teammate, quantity: request.order_lines.last.quantity)

      assert_equal addresses(@requester, @world.buyer), emailed, "not the teammate who received the last item"
    end
  end

  test "marking everything received tells them once" do
    with_notices do
      request = start(approved_request(@world, lines: [ { description: "Gear", price: 10 }, { description: "Belt", price: 5 } ]))
      buy(@world, request.order_lines.to_a, vendor: @world.preferred_vendor)
      clear_enqueued_jobs
      request.mark_all_received!(by: @world.teammate)

      assert_equal addresses(@requester, @world.buyer), emailed
    end
  end

  test "the requester who marks everything received isn't told" do
    with_notices do
      request = start(approved_request(@world))
      buy(@world, request.order_lines.to_a, vendor: @world.preferred_vendor)
      clear_enqueued_jobs
      request.mark_all_received!(by: @requester)

      assert_equal addresses(@world.buyer), emailed
    end
  end

  test "reloading code doesn't make the received notice send twice" do
    with_notices do
      request = start(approved_request(@world))
      buy(@world, request.order_lines.to_a, vendor: @world.preferred_vendor)
      clear_enqueued_jobs
      2.times { Rails.application.reloader.prepare! }
      request.mark_all_received!(by: @world.teammate)

      assert_equal addresses(@requester, @world.buyer), emailed
    end
  end

  test "a problem with delivery goes to the buyer who ordered it, and no one else" do
    with_notices do
      request = start(approved_request(@world))
      request.follow!(@world.teammate)
      buy(@world, request.order_lines.to_a, vendor: @world.preferred_vendor)
      clear_enqueued_jobs
      line = request.order_lines.first
      line.record_delivery!(by: @requester, quantity: line.quantity, condition: :damaged, note: "Cracked")

      assert_equal addresses(@world.buyer), emailed
      assert_match "Problem with delivery", enqueued_emails.first[1]
    end
  end

  test "needing approval again goes to the final step's approvers" do
    with_notices(**two_step_settings(@world)) do
      request = start(submitted_request(@world, lines: [ { description: "Router", price: 600 } ]))
      request.decide!(:approved, by: @world.mentor)
      request.decide!(:approved, by: @world.manager)
      clear_enqueued_jobs
      line = request.order_lines.first
      buy(@world, [ line ], vendor: @world.preferred_vendor, prices: { line.id => 90_000 })

      assert_equal "needs_reapproval", line.reload.status
      again = enqueued_emails.select { |_address, subject, _body| subject.include?("Approve again") }
      assert_equal addresses(@world.manager, @world.admin), again.map(&:first).sort
    end
  end

  test "approving or declining the changed items again tells the requester only" do
    with_notices do
      request = start(approved_request(@world))
      request.follow!(@world.teammate)
      line = request.order_lines.first
      buy(@world, [ line ], vendor: @world.preferred_vendor, prices: { line.id => 90_000 })
      clear_enqueued_jobs
      request.decide!(:approved, by: @world.mentor)

      assert_equal addresses(@requester), emailed
      assert_match "Approved: ", enqueued_emails.first[1]
    end

    with_notices do
      request = start(approved_request(@world))
      request.follow!(@world.teammate)
      line = request.order_lines.first
      buy(@world, [ line ], vendor: @world.preferred_vendor, prices: { line.id => 90_000 })
      clear_enqueued_jobs
      request.decide!(:declined, by: @world.mentor, comment: "Too dear")

      assert_equal addresses(@requester), emailed
      assert_match "Too dear", email_to(@requester)
    end
  end

  test "nothing is sent while Orders is off" do
    request = nil
    with_notices { request = start }
    with_orders(@world, feature_orders: "false") do
      request.decide!(:approved, by: @world.mentor)
      OrderNotices.new.submitted(request)

      assert_empty emailed
    end
  end

  test "someone without an email address is left out" do
    with_notices do
      @world.mentor.user.update_columns(email: "")
      draft = draft_request(@world)
      clear_enqueued_jobs
      draft.submit!(by: @requester)

      assert_equal addresses(@world.manager, @world.admin), emailed
    end
  end

  test "a notice that fails doesn't undo the change" do
    with_notices do
      draft = draft_request(@world)
      OrderNotices.define_singleton_method(:new) { |*| raise "mail is down" }
      begin
        draft.submit!(by: @requester)
      ensure
        OrderNotices.singleton_class.remove_method(:new)
      end

      assert_predicate draft.reload, :submitted?
    end
  end

  test "deliver keeps its signature and gets only the people who hear, for a connector to prepend onto" do
    assert_equal [ %i[req people], %i[req subject], %i[key by] ], OrderNotices.instance_method(:deliver).parameters

    with_notices(orders_notices: "daily") do
      with_personal_choices(@world.mentor => :each) do
        given = []
        notices = OrderNotices.new
        notices.singleton_class.prepend(Module.new do
          define_method(:deliver) do |people, subject, by: nil, &block|
            given.concat(people)
            super(people, subject, by: by, &block)
          end
        end)
        notices.submitted(start)

        assert_equal [ @world.mentor ], given
      end
    end
  end

  test "each notice is its own method on OrderNotices, for a connector to prepend onto" do
    expected = %i[submitted step_approved approved changes_requested declined ordered backordered received problem
      needs_reapproval needed_soon undecided digest]
    assert_empty expected - OrderNotices.public_instance_methods(false)
  end

  # -- each person's choice (orders_notices, Orders::Config.delivery_for) ---

  # Submitted, approved, ordered and received: every event an approver, a
  # requester or a buyer hears of.
  def run_through
    draft = draft_request(@world)
    draft.follow!(@world.teammate)
    clear_enqueued_jobs
    draft.submit!(by: @requester)
    draft.decide!(:approved, by: @world.mentor)
    buy(@world, draft.order_lines.to_a, vendor: @world.preferred_vendor)
    draft.mark_all_received!(by: @world.manager)
  end

  test "with the site's choice in the daily digest, nobody gets an email as things happen" do
    with_notices(orders_notices: "daily") do
      run_through

      assert_empty emailed
    end
  end

  test "with the site's choice in the Weekly Infodump or off, nobody gets an email as things happen" do
    %w[weekly off].each do |choice|
      with_notices(orders_notices: choice) do
        run_through

        assert_empty emailed, choice
      end
    end
  end

  test "the site's choice of an email each time reaches approvers, requesters, watchers and buyers" do
    with_notices do
      run_through

      subjects = enqueued_emails.map { |address, subject, _body| [ address, subject[/ - (\w+( \w+)?):/, 1] ] }
      assert_includes subjects, [ @world.mentor.user.email, "To approve" ]
      assert_includes subjects, [ @requester.user.email, "Approved" ]
      assert_includes subjects, [ @world.teammate.user.email, "Ordered" ]
      assert_includes subjects, [ @world.buyer.user.email, "To buy" ]
      assert_includes subjects, [ @requester.user.email, "Here" ]
    end
  end

  test "each person's own choice beats the site's, for approvers, requesters and buyers" do
    with_notices(orders_notices: "daily") do
      with_personal_choices(@world.mentor => :each, @requester => :each, @world.teammate => :off, @world.buyer => :each) do
        run_through

        assert_equal addresses(@world.mentor, @requester, @requester, @requester, @world.buyer, @world.buyer), emailed
      end
    end

    with_notices do
      with_personal_choices(@world.mentor => :daily, @world.manager => :weekly, @world.admin => :off) do
        draft = draft_request(@world)
        clear_enqueued_jobs
        draft.submit!(by: @requester)

        assert_empty emailed
      end
    end
  end

  test "a person's choice comes from Summaries where it offers one, else the site's" do
    with_orders(@world, orders_notices: "weekly") do
      assert_equal :weekly, Orders::Config.delivery_for(@requester)

      with_personal_choices(@requester => :each, @world.teammate => :both, @world.buyer => :nonsense) do
        assert_equal :each, Orders::Config.delivery_for(@requester)
        assert_equal :daily, Orders::Config.delivery_for(@world.teammate)
        assert_equal :weekly, Orders::Config.delivery_for(@world.buyer)
        assert_equal :weekly, Orders::Config.delivery_for(@world.mentor)
      end
    end
  end

  test "an unknown site choice counts as the daily digest" do
    with_orders(@world, orders_notices: "sometimes") do
      assert_equal :daily, Orders::Config.notices
    end
    with_orders(@world) do
      assert_equal :daily, Orders::Config.notices, "the default"
    end
  end
end
