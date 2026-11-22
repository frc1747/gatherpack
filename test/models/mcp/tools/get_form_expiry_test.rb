require "test_helper"
require_relative "../../../support/mcp_world"
require_relative "../../../support/mcp_forms_world"
require_relative "../../../support/mcp_form_responses_world"

class Mcp::Tools::GetFormExpiryTest < ActiveSupport::TestCase
  include McpWorld
  include McpFormsWorld
  include McpFormResponsesWorld

  setup do
    build_mcp_world
    build_mcp_forms_world
    build_mcp_form_responses_world
  end

  def get_form(viewer, subject = nil, form: @lunch)
    arguments = { form_id: form.neat_id }
    arguments[:person_id] = person(subject).neat_id if subject
    call_tool("get_form", user: user(viewer), **arguments)
  end

  def form_expiry(result)
    result.value["form"].values_at("expires_on", "valid_for_months")
  end

  test "a form with no expiry shows none" do
    assert_equal [ nil, nil ], form_expiry(get_form(:admin))
    assert_nil get_form(:admin, :alpha_member).value["response"]["expires_at"]
  end

  test "a form's expiry date shows to those who may edit its details" do
    @lunch.update!(expires_on: Date.new(2031, 6, 1))

    %i[ admin alpha_manager ].each { |viewer| assert_equal [ "2031-06-01", nil ], form_expiry(get_form(viewer)) }
  end

  test "months after signing show to those who may edit its details" do
    @lunch.update!(valid_for_months: 12)

    assert_equal [ nil, 12 ], form_expiry(get_form(:alpha_manager))
  end

  test "the expiry rule stays out for those who may not edit the form's details" do
    @lunch.update!(expires_on: Date.new(2031, 6, 1))

    assert_equal [ nil, nil ], form_expiry(get_form(:alpha_member, :alpha_member))
    assert_equal [ nil, nil ], form_expiry(get_form(:coordinator))
  end

  test "a response says when it stops counting" do
    @lunch.update!(expires_on: Date.new(2031, 6, 1))
    response = get_form(:alpha_member, :alpha_member).value["response"]

    assert_equal "complete", response["status"]
    assert_equal Date.new(2031, 6, 1).in_time_zone.iso8601, response["expires_at"]

    @lunch.update!(expires_on: nil, valid_for_months: 6)
    signed = @lunch.form_responses.find_by!(subject: person(:alpha_member)).active_submission.activated_at
    assert_equal (signed + 6.months).iso8601, get_form(:alpha_member, :alpha_member).value["response"]["expires_at"]
  end

  test "a response past its expiry reads needs_reconfirmation here, in form_status and in the form's report" do
    @lunch.update!(valid_for_months: 1)

    travel_to 2.months.from_now do
      assert_equal "needs_reconfirmation", get_form(:alpha_member, :alpha_member).value["response"]["status"]
      by_status = call_tool("form_status", user: user(:admin), form_id: @lunch.neat_id).value["counts"]["by_status"]
      assert_equal 2, by_status["needs_reconfirmation"]
      assert_equal 0, by_status["complete"].to_i
    end
  end

  test "a response is complete until its expiry date" do
    @lunch.update!(expires_on: Date.current + 2)

    assert_equal "complete", get_form(:alpha_member, :alpha_member).value["response"]["status"]
    travel_to 3.days.from_now do
      assert_equal "needs_reconfirmation", get_form(:alpha_member, :alpha_member).value["response"]["status"]
    end
  end
end
