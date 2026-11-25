require "test_helper"
require "support/orders_world"

# The approvers emailed for each step on a request's page, from the sent
# email log (BL-054).
class Orders::ApprovalEmailsTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers
  include OrdersWorld

  setup do
    @world = build_orders_world
    @sent_at = Time.zone.parse("2026-11-20 20:19:00")
  end

  def with_email_log(**overrides, &block)
    with_orders(@world, feature_email_log: "true", **overrides, &block)
  end

  def logged(request, person, sent_at: @sent_at, clicked_at: nil, status: "delivered")
    entry = SentEmail.create!(address: person.user.email, person: person, about: request, subject: "To approve",
      status: status, sent_at: sent_at, delivered_at: sent_at + 1.second, created_at: sent_at)
    entry.update!(first_clicked_at: clicked_at, click_count: 1) if clicked_at
    entry
  end

  test "an approver sees who was emailed for the step and when they clicked a link" do
    with_email_log do
      request = submitted_request(@world)
      logged(request, @world.mentor, clicked_at: @sent_at + 7.minutes)
      logged(request, @world.manager)
      sign_in @world.mentor.user

      get orders_request_url(request)

      assert_select "#approval-emails" do
        assert_select "h3", "Approval"
        assert_select "li", text: /Mentor Example:\s+Emailed 8:19 PM November 20, 2026 · Link clicked 8:26 PM November 20, 2026/
        assert_select "li", text: /Manager Example:\s+Emailed 8:19 PM November 20, 2026, not clicked yet/
      end
      assert_no_match(/\bread\b/i, css_select("#approval-emails").text)
    end
  end

  test "a click a mail scanner made as the email arrived isn't shown" do
    with_email_log do
      request = submitted_request(@world)
      logged(request, @world.mentor, clicked_at: @sent_at + 3.seconds)
      sign_in @world.admin.user

      get orders_request_url(request)

      assert_select "#approval-emails li", text: /Mentor Example:\s+Emailed .*, not clicked yet/
    end
  end

  test "a bounced email shows the problem" do
    with_email_log do
      request = submitted_request(@world)
      logged(request, @world.mentor, status: "bounced")
      sign_in @world.manager.user

      get orders_request_url(request)

      assert_select "#approval-emails li .text-danger", "Bounced"
    end
  end

  test "each step lists the approvers emailed while it waited" do
    with_email_log(**two_step_settings(@world)) do
      request = submitted_request(@world, lines: [ { description: "Router", price: 600 } ])
      logged(request, @world.mentor)
      travel_to(@sent_at + 1.hour) { request.decide!(:approved, by: @world.mentor) }
      logged(request, @world.manager, sent_at: @sent_at + 2.hours)
      sign_in @world.admin.user

      get orders_request_url(request)

      assert_select "#approval-emails" do
        assert_equal [ "Mentor", "Treasurer" ], css_select("#approval-emails h3").map(&:text)
        assert_select "ul:nth-of-type(1) li", 1
        assert_select "ul:nth-of-type(1) li", /Mentor Example/
        assert_select "ul:nth-of-type(2) li", 1
        assert_select "ul:nth-of-type(2) li", /Manager Example: \s*Emailed 10:19 PM/
      end
    end
  end

  test "people who can't approve or manage the request don't see the emails" do
    with_email_log do
      request = submitted_request(@world)
      logged(request, @world.mentor)

      [ @world.requester, @world.teammate, @world.buyer, @world.parent ].each do |person|
        sign_in person.user
        get orders_request_url(request)

        assert_response :success
        assert_select "#approval-emails", 0, "#{person.first_name} shouldn't see the approval emails"
        sign_out person.user
      end
    end
  end

  test "nothing is shown with the email log off" do
    with_orders(@world) do
      request = submitted_request(@world)
      logged(request, @world.mentor)
      sign_in @world.admin.user

      get orders_request_url(request)

      assert_response :success
      assert_select "#approval-emails", 0
    end
  end

  test "nothing is shown when no email about the request was logged" do
    with_email_log do
      request = submitted_request(@world)
      sign_in @world.admin.user

      get orders_request_url(request)

      assert_select "#approval-emails", 0
    end
  end
end
