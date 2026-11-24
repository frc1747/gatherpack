require "test_helper"
require "support/orders_world"
require "support/order_notices_helper"

# With notices_admins_everywhere off, admins hear about requests only through
# their own roles, or when nobody else would; what they may do is unchanged.
class Orders::AdminNoticesTest < ActiveSupport::TestCase
  include ActiveJob::TestHelper
  include OrdersWorld
  include OrderNoticesHelper

  setup do
    @world = build_orders_world
    @admin = @world.admin
  end

  def with_notices(everywhere: "false", **overrides, &block)
    with_orders(@world, orders_notices: "each", notices_admins_everywhere: everywhere, **overrides, &block)
  end

  def submit(**attributes)
    draft = draft_request(@world, **attributes)
    clear_enqueued_jobs
    draft.submit!(by: draft.requested_by)
    draft
  end

  def manage(person, team)
    Membership.create!(person: person, team: team, manager: true)
  end

  test "the setting is on unless a site turns it off" do
    setting = Settings.get(:notices_admins_everywhere)

    assert_equal "true", setting.default_value
    assert_equal :boolean, setting.setting_type
    assert setting.in_group?("Notifications")
  end

  test "with the setting on, an admin hears of every team's requests" do
    with_notices(everywhere: "true") do
      request = submit
      assert_equal addresses(@world.mentor, @world.manager, @admin), emailed

      clear_enqueued_jobs
      request.decide!(:approved, by: @world.mentor)
      assert_equal addresses(@world.requester, @world.buyer, @world.manager, @admin), emailed
    end
  end

  test "with the setting off, an admin outside the step's reach isn't told of a submitted or approved request" do
    with_notices do
      request = submit
      assert_equal addresses(@world.mentor, @world.manager), emailed

      clear_enqueued_jobs
      request.decide!(:approved, by: @world.mentor)
      assert_equal addresses(@world.requester, @world.buyer, @world.manager), emailed
    end
  end

  test "with the setting off, an admin who isn't on the next step isn't told of the step approval" do
    with_notices(**two_step_settings(@world)) do
      request = submit(lines: [ { description: "Router", price: 600 } ])
      clear_enqueued_jobs
      request.decide!(:approved, by: @world.mentor)

      assert_equal addresses(@world.manager), emailed
    end
  end

  test "managing another team doesn't bring an admin this team's notices" do
    manage(@admin, @world.art)

    with_notices do
      request = submit
      assert_equal addresses(@world.mentor, @world.manager), emailed
      assert_not_includes Orders::Recipients.buyers(@world.robotics.id), @admin

      clear_enqueued_jobs
      submit(team: @world.art, by: @world.outsider)
      assert_equal addresses(@admin), emailed
      assert_equal [ @admin ], Orders::Recipients.buyers(@world.art.id)
      assert request.can_decide?(@admin)
    end
  end

  test "an admin in the step's reach by a manager flag on a team above is still told" do
    manage(@admin, @world.club)

    with_notices do
      submit

      assert_equal addresses(@world.mentor, @world.manager, @admin), emailed
    end
  end

  test "an admin in the step's reach by a badge is still told" do
    BadgeAssignment.create!(badge: @world.approver_badge, person: @admin)
    Membership.create!(person: @admin, team: @world.robotics)

    with_notices do
      submit

      assert_equal addresses(@world.mentor, @world.manager, @admin), emailed
    end
  end

  test "an admin with a buyer role is still told what's ready to buy" do
    Membership.create!(person: @admin, team: @world.robotics)
    BadgeAssignment.create!(badge: @world.buyer_badge, person: @admin)

    with_notices do
      assert_equal addresses(@world.buyer, @world.manager, @admin), addresses(*Orders::Recipients.buyers(@world.robotics.id))
    end
  end

  test "a step and a team nobody else holds fall back to admins" do
    with_notices do
      request = submit(team: @world.art, by: @world.outsider)
      assert_equal addresses(@admin), emailed

      clear_enqueued_jobs
      request.decide!(:approved, by: @admin)
      assert_equal [ @admin ], Orders::Recipients.buyers(@world.art.id)
    end
  end

  test "approvers who turned order emails off don't count as someone to tell" do
    with_notices do
      with_personal_choices(@world.mentor => :off, @world.manager => :off) do
        submit

        assert_equal addresses(@admin), emailed
      end
    end
  end

  test "an approver who reads a summary counts, so admins aren't told" do
    with_notices do
      with_personal_choices(@world.mentor => :daily, @world.manager => :off) do
        submit

        assert_empty emailed
      end
    end
  end

  test "an admin's own request doesn't fall back to them" do
    with_notices do
      request = submit(team: @world.art, by: @admin)

      assert_empty Orders::Recipients.approvers(request, request.current_step)
    end
  end

  test "reminders follow the same recipients" do
    with_notices do
      request = submit(needed_by: Date.current + 1)

      clear_enqueued_jobs
      OrderNotices.new.undecided(request)
      assert_equal addresses(@world.mentor, @world.manager), emailed

      clear_enqueued_jobs
      OrderNotices.new.needed_soon(request)
      assert_equal addresses(@world.mentor, @world.manager), emailed
    end
  end

  def summary(person)
    Orders::Current.reset
    Orders::Digest.new(person, since: 1.day.ago)
  end

  # A request bought at a price past the tolerance, so it waits for the final
  # step's approval again.
  def reapproval_request(**attributes)
    order_request = approved_request(@world, **attributes)
    # Only an admin buys for art, which the buyer badge doesn't reach.
    buyer = order_request.team_id == @world.art.id ? @admin : @world.buyer
    Orders::RecordPurchase.new(buyer: buyer, lines: order_request.order_lines.to_a, other_vendor_name: "Corner Store",
      prices: { order_request.order_lines.first.id => 100_00 }, attributes: { ordered_on: Date.current }).call
    order_request.reload
  end

  test "with the setting off, an admin's summary lists only the teams their roles reach" do
    manage(@admin, @world.art)
    ours = theirs = our_purchase = their_purchase = our_change = their_change = nil
    with_orders(@world) do
      ours = submit(team: @world.art, by: @world.outsider)
      theirs = submit
      our_purchase = approved_request(@world, team: @world.art, by: @world.outsider)
      their_purchase = approved_request(@world)
      our_change = reapproval_request(team: @world.art, by: @world.outsider)
      their_change = reapproval_request
    end

    with_notices(orders_notices: "daily") do
      digest = summary(@admin)

      assert_equal [ ours ], digest.to_approve
      assert_equal [ our_change ], digest.to_reapprove
      assert_equal [ our_purchase ], digest.to_buy
    end

    with_notices(everywhere: "true", orders_notices: "daily") do
      digest = summary(@admin)

      assert_equal [ ours, theirs ].sort_by(&:id), digest.to_approve.sort_by(&:id)
      assert_equal [ our_change, their_change ].sort_by(&:id), digest.to_reapprove.sort_by(&:id)
      assert_equal [ our_purchase, their_purchase ].sort_by(&:id), digest.to_buy.sort_by(&:id)
    end
  end

  test "an admin with no role has an empty summary while others approve and buy" do
    with_orders(@world) do
      submit
      approved_request(@world)
      reapproval_request
    end

    with_notices(orders_notices: "daily") do
      assert summary(@admin).empty?
      assert_equal 1, summary(@world.mentor).to_approve.size
      assert_equal 1, summary(@world.mentor).to_reapprove.size
      assert_equal 1, summary(@world.buyer).to_buy.size
    end
  end

  test "an admin's summary lists what nobody else approves or buys" do
    waiting = bought = changed = nil
    with_orders(@world) do
      waiting = submit(team: @world.art, by: @world.outsider)
      bought = approved_request(@world, team: @world.art, by: @world.outsider)
      changed = reapproval_request(team: @world.art, by: @world.outsider)
    end

    with_notices(orders_notices: "daily") do
      digest = summary(@admin)

      assert_equal [ waiting ], digest.to_approve
      assert_equal [ changed ], digest.to_reapprove
      assert_equal [ bought ], digest.to_buy
    end
  end

  test "an admin's pages still list every team's requests" do
    with_notices do
      request = submit
      Orders::Current.reset

      assert_includes Orders::WaitingOn.for(@admin).to_approve, request
    end
  end

  test "an admin may still do everything" do
    with_notices do
      request = submit

      assert request.can_decide?(@admin)
      assert OrderRequestPolicy.new(@admin.user, request).show?
      access = Orders::Access.for(@admin)
      assert access.admin?
      assert access.buyer_for?(@world.art.id)
      assert access.funding_manager_for?(@world.art.id)
      request.decide!(:approved, by: @admin)
      assert request.approved?
    end
  end
end
