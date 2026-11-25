require "test_helper"
require "support/orders_world"

# Which logged emails count as an approver's for each step of a request.
class EmailLog::OrderRequestEmailsTest < ActiveSupport::TestCase
  include OrdersWorld

  setup do
    @world = build_orders_world
    @at = 1.hour.from_now
  end

  def logged(request, person, at:, subject:, clicked_at: nil)
    SentEmail.create!(address: person.user.email, person: person, about: request, subject: subject,
      status: "delivered", sent_at: at, delivered_at: at + 1.second, created_at: at,
      first_clicked_at: clicked_at, click_count: clicked_at ? 1 : 0)
  end

  def approvers_by_step(request)
    EmailLog::OrderRequestEmails.new(request.reload).steps.map { |step| [ step.step.key, step.approvers.map(&:person) ] }
  end

  test "a Declined email to an approver who follows the request isn't an approval email" do
    with_orders(@world, feature_email_log: "true") do
      request = submitted_request(@world)
      request.follow!(@world.mentor)
      travel_to(@at) { request.decide!(:declined, by: @world.manager, comment: "No") }
      logged(request, @world.mentor, at: @at + 1.minute, subject: "Declined: Gear", clicked_at: @at + 5.minutes)

      assert_equal [ [ "approval", [] ] ], approvers_by_step(request)
    end
  end

  test "a Needs changes email isn't an approval email, but the one after resubmitting is" do
    with_orders(@world, feature_email_log: "true") do
      request = submitted_request(@world)
      request.follow!(@world.mentor)
      travel_to(@at) { request.decide!(:changes_requested, by: @world.manager, comment: "Which size?") }
      logged(request, @world.mentor, at: @at + 1.minute, subject: "Needs changes: Gear", clicked_at: @at + 5.minutes)
      travel_to(@at + 1.hour) { request.resubmit!(by: @world.requester, comment: "The big one") }
      resent = logged(request, @world.manager, at: @at + 1.hour + 1.second, subject: "To approve: Gear")

      steps = EmailLog::OrderRequestEmails.new(request.reload).steps
      assert_equal [ @world.manager ], steps.first.approvers.map(&:person)
      assert_equal resent.sent_at, steps.first.approvers.first.emailed_at
    end
  end

  test "a re-approval doesn't stretch the final step over the emails sent once it was approved" do
    with_orders(@world, feature_email_log: "true") do
      request = submitted_request(@world)
      logged(request, @world.mentor, at: @at - 1.minute, subject: "To approve: Gear")
      travel_to(@at) { request.decide!(:approved, by: @world.mentor) }
      logged(request, @world.admin, at: @at + 1.minute, subject: "To buy: Gear", clicked_at: @at + 5.minutes)
      travel_to(@at + 1.day) { request.order_approvals.create!(step_key: "approval", approver: @world.manager, decision: "approved") }

      assert_equal [ [ "approval", [ @world.mentor ] ] ], approvers_by_step(request)
    end
  end
end
