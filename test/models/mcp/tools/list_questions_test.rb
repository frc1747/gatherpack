require "test_helper"
require_relative "../../../support/mcp_world"

class Mcp::Tools::ListQuestionsTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers
  include McpWorld

  setup do
    host! "localhost"
    build_mcp_world
    Question.destroy_all
    @alpha_question = Question.create!(title: "Alpha question", content: "Asking", team: @alpha, person: person(:alpha_member), created_at: 2.days.ago)
    @beta_question = Question.create!(title: "Beta question", content: "Asking", team: @beta, person: person(:beta_member), created_at: 1.day.ago)
    @closed = Question.create!(title: "Closed question", content: "Asked", team: @alpha, person: person(:alpha_manager), closed: true, created_at: 3.days.ago)
    top = @alpha_question.replies.create!(content: "Answer", person: person(:ward))
    @alpha_question.replies.create!(content: "Follow-up", person: person(:alpha_manager), parent: top)
  end

  def titles(viewer, **options)
    call_tool("list_questions", user: user(viewer), **options).value["items"].map { |item| item["title"] }
  end

  test "an admin sees open questions on every team, newest first" do
    assert_equal [ "Beta question", "Alpha question" ], titles(:admin)
  end

  test "a team manager and a member see their team's" do
    assert_equal [ "Alpha question" ], titles(:alpha_manager)
    assert_equal [ "Alpha question" ], titles(:alpha_member)
  end

  test "a plain member on another team sees only theirs, and a guardian on no team none" do
    assert_equal [ "Beta question" ], titles(:beta_member)
    assert_equal [], titles(:guardian)
  end

  test "open false lists closed ones, and true the same as the default" do
    assert_equal [ "Closed question" ], titles(:alpha_member, open: false)
    assert_equal [ "Alpha question" ], titles(:alpha_member, open: true)
    assert_equal [], titles(:beta_member, open: false)
    assert_match(/open/, call_tool("list_questions", user: user(:admin), open: "no").error)
  end

  # Only as an admin: for anyone else the index's policy(Question).create? fails on the class.
  test "it lists what the index lists" do
    sign_in user(:admin)
    get questions_path

    [ "Alpha question", "Beta question", "Closed question" ].each do |title|
      assert_equal response.body.include?(title), titles(:admin).include?(title), title
    end
  end

  test "it lists what the question pages open" do
    %i[alpha_manager beta_member guardian].each do |viewer|
      opens = [ @alpha_question, @beta_question ].select do |question|
        sign_in user(viewer)
        get question_path(question)
        sign_out user(viewer)
        response.successful?
      end

      assert_equal opens.map(&:title).sort, titles(viewer).sort, viewer
    end
  end

  test "items carry the author, team and every reply in the count, but not the text" do
    result = call_tool("list_questions", user: user(:alpha_member))
    item = result.value["items"].first

    assert_equal @alpha_question.neat_id, item["id"]
    assert_equal person(:alpha_member).neat_id, item.dig("asked_by", "id")
    assert_equal({ "id" => @alpha.neat_id, "name" => "Alpha" }, item["team"])
    assert_equal false, item["closed"]
    assert_equal 2, item["reply_count"]
    assert_not_includes result.value.to_json, "Asking"
  end

  test "the team filter stays within what the viewer can see" do
    assert_equal [ "Alpha question" ], titles(:admin, team_id: @alpha.neat_id)
    assert_equal "Not found", call_tool("list_questions", user: user(:beta_member), team_id: @alpha.neat_id).error
    assert_equal "Not found", call_tool("list_questions", user: user(:admin), team_id: "nonsense").error
  end

  test "the feature being off refuses it" do
    with_feature(:qa, false) { assert_equal "Feature off", call_tool("list_questions", user: user(:admin)).error }
  end
end
