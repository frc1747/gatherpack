require "test_helper"
require_relative "../../../support/mcp_world"

class Mcp::Tools::GetQuestionTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers
  include McpWorld

  setup do
    host! "localhost"
    build_mcp_world
    base = Time.utc(2026, 3, 1)
    @question = Question.create!(title: "Which day?", content: "Asking *now*", team: @alpha, person: person(:alpha_member), created_at: base)
    @first = @question.replies.create!(content: "Monday", person: person(:ward), created_at: base + 1.hour)
    @second = @question.replies.create!(content: "Tuesday", person: person(:alpha_manager), created_at: base + 2.hours)
    @nested = @question.replies.create!(content: "Why Monday?", person: person(:alpha_member), parent: @first, created_at: base + 3.hours)
    @deep = @question.replies.create!(content: "Because", person: person(:ward), parent: @nested, created_at: base + 4.hours)
    ReplyVote.create!(reply: @second, person: person(:ward), question: @question)
    @beta_question = Question.create!(title: "Beta?", content: "x", team: @beta, person: person(:beta_member))
  end

  def question(viewer, target = @question)
    call_tool("get_question", user: user(viewer), question_id: target.neat_id)
  end

  test "an admin, a team manager and a member get it" do
    %i[admin alpha_manager alpha_member].each { |viewer| assert_equal "Which day?", question(viewer).value["title"], viewer }
  end

  test "a plain member on another team and a guardian on no team get not found" do
    assert_equal "Not found", question(:beta_member).error
    assert_equal "Not found", question(:guardian).error
    assert_equal "Beta?", question(:beta_member, @beta_question).value["title"]
  end

  test "it opens and refuses as the page does" do
    %i[admin alpha_manager alpha_member beta_member guardian].product([ @question, @beta_question ]).each do |viewer, target|
      sign_in user(viewer)
      get question_path(target)
      sign_out user(viewer)

      assert_equal response.successful?, question(viewer, target).error.nil?, "#{viewer} opening #{target.title}"
    end
  end

  test "replies come in the page's order with who wrote them" do
    value = question(:alpha_member).value

    assert_equal "Asking *now*", value["content"]
    assert_equal person(:alpha_member).neat_id, value.dig("asked_by", "id")
    assert_equal [ @first, @nested, @deep, @second ].map(&:neat_id), value["replies"].map { |reply| reply["id"] }
    assert_equal [ nil, @first.neat_id, @nested.neat_id, nil ], value["replies"].map { |reply| reply["parent_id"] }
    assert_equal [ "World", "World", "World", "World" ], value["replies"].map { |reply| reply.dig("person", "name").split.last }
    assert_equal person(:ward).neat_id, value["replies"].first.dig("person", "id")
  end

  test "the page's top reply is marked, its vote count isn't given, and the viewer's own vote is" do
    ward = question(:ward).value
    assert_equal [ false, false, false, true ], ward["replies"].map { |reply| reply["promoted"] }
    assert_equal @second.neat_id, ward["voted_reply_id"]
    assert_nil question(:alpha_member).value["voted_reply_id"]
    assert_not_includes ward["replies"].first.keys, "votes"
  end

  test "a closed question still opens" do
    @question.update!(closed: true)
    assert_equal true, question(:alpha_member).value["closed"]
  end

  test "invalid IDs are not found, and the feature being off refuses it" do
    [ "nonsense", @alpha.neat_id ].each { |bad| assert_equal "Not found", call_tool("get_question", user: user(:admin), question_id: bad).error }
    with_feature(:qa, false) { assert_equal "Feature off", question(:admin).error }
  end
end
