require "test_helper"
require_relative "../../../support/mcp_world"
require_relative "../../../support/mcp_forms_world"

# Counts FormResponsePolicy#show? calls while ShowCounter.count is a number.
module ShowCounter
  class << self
    attr_accessor :count
  end

  def show?
    ShowCounter.count += 1 if ShowCounter.count
    super
  end
end
FormResponsePolicy.prepend(ShowCounter)

class Mcp::Tools::FormAnswersTest < ActiveSupport::TestCase
  include McpWorld
  include McpFormsWorld

  setup do
    build_mcp_world
    build_mcp_forms_world
  end

  def answers(viewer, form = @lunch, **args)
    call_tool("form_answers", user: user(viewer), form_id: form.neat_id, **args)
  end

  def by_person(result, name)
    result.value["items"].find { |entry| entry["person"]["name"] == name }
  end

  def by_label(item, label)
    item["answers"].find { |answer| answer["label"] == label }
  end

  test "an admin sees every submitted answer, only for people who submitted" do
    result = answers(:admin)
    member = by_person(result, "AlphaMember World")

    assert_equal [ "AlphaMember World", "Ward World" ], result.value["items"].map { |entry| entry["person"]["name"] }
    assert_equal "Slim 4", by_label(member, "Sandwich")["answer"]
    assert_equal "no onions", by_label(member, "Notes")["answer"]
    assert_equal "peanut", by_label(member, "Allergies")["answer"]
    assert_equal 1, member["submission"]["number"]
    assert_equal @sandwich.neat_id, by_label(member, "Sandwich")["question_id"]
  end

  test "a team manager sees the answers their read levels reach, and not the person-field answer" do
    member = by_person(answers(:alpha_manager), "AlphaMember World")

    assert_equal "Slim 4", by_label(member, "Sandwich")["answer"]
    assert_equal "no onions", by_label(member, "Notes")["answer"]
    allergies = by_label(member, "Allergies")
    assert_not allergies["readable"]
    assert_nil allergies["answer"]
  end

  test "a badge-granted coordinator doesn't see answers whose level only leaders reach beyond the grant" do
    member = by_person(answers(:coordinator), "AlphaMember World")

    assert_equal "Slim 4", by_label(member, "Sandwich")["answer"]
    assert by_label(member, "Notes")["readable"], "a read grant acts as a leader"
    assert_not by_label(member, "Allergies")["readable"]
  end

  test "a person in the audience is not allowed, even for their own answers" do
    assert_equal "Not allowed", answers(:alpha_member).error
    assert_equal "Not allowed", answers(:alpha_member, person_id: person(:alpha_member).neat_id).error
  end

  test "a guardian answering for a ward is not allowed" do
    assert_equal "Not allowed", answers(:guardian).error
  end

  test "a member of another team is not allowed" do
    assert_equal "Not allowed", answers(:beta_member).error
  end

  test "person_id narrows to one person" do
    result = answers(:admin, person_id: person(:ward).neat_id)

    assert_equal [ "Ward World" ], result.value["items"].map { |entry| entry["person"]["name"] }
    assert_equal "Big John", by_label(result.value["items"].first, "Sandwich")["answer"]
  end

  test "a coordinator can ask about a person the grant reaches outside their teams" do
    result = answers(:coordinator, person_id: person(:alpha_member).neat_id)

    assert_equal [ "AlphaMember World" ], result.value["items"].map { |entry| entry["person"]["name"] }
    assert_equal "Not found", answers(:coordinator, person_id: person(:beta_member).neat_id).error
  end

  test "a manager of one team sees only that team's answers on a form that asks two" do
    names = answers(:alpha_manager, @cross).value["items"].map { |entry| entry["person"]["name"] }

    assert_equal [ "AlphaMember World" ], names
    assert_equal "Not found", answers(:alpha_manager, @cross, person_id: person(:beta_member).neat_id).error
    assert_equal 3, answers(:admin, @cross).value["items"].size
  end

  test "a question with its own read level is hidden from a viewer it excludes" do
    manager = by_label(by_person(answers(:alpha_manager, @cross), "AlphaMember World"), "Medical")
    admin = by_label(by_person(answers(:admin, @cross), "AlphaMember World"), "Medical")

    assert_not manager["readable"]
    assert_nil manager["answer"]
    assert admin["readable"]
  end

  test "a grant limited to a team shows that team's answers only" do
    names = answers(:alpha_member, @cross).value["items"].map { |entry| entry["person"]["name"] }

    assert_equal [ "AlphaMember World" ], names
  end

  test "withdrawn and draft-only responses have no answers to show, a former subject's stay" do
    assert_equal [ "AlphaManager World", "BetaMember World" ], answers(:admin, @mixed).value["items"].map { |entry| entry["person"]["name"] }
  end

  test "people with the same name come in ID order, and the response check stops at the limit" do
    twins = 2.times.map do |n|
      user = User.create!(email: "twin#{n}@example.com", password: "Password1!")
      twin = Person.create!(user: user, first_name: "Twin", last_name: "World")
      Membership.create!(person: twin, team: @alpha)
      @people[:"twin#{n}"] = twin
      respond_to_form(@lunch, :"twin#{n}", as: :"twin#{n}", answers: { "sandwich" => "Slim 4" })
      twin
    end

    ids = answers(:admin).value["items"].select { |entry| entry["person"]["name"] == "Twin World" }.map { |entry| entry["person"]["id"] }
    assert_equal twins.sort_by(&:id).map(&:neat_id), ids

    ShowCounter.count = 0
    result = answers(:admin, limit: 1)
    assert_equal 2, ShowCounter.count
    assert result.value["truncated"]
  ensure
    ShowCounter.count = nil
  end

  test "person_id of someone who hasn't answered gives no items, and of someone unseen is not found" do
    assert_empty answers(:admin, person_id: person(:alpha_manager).neat_id).value["items"]
    assert_equal "Not found", answers(:alpha_manager, person_id: person(:beta_member).neat_id).error
  end

  test "an unsubmitted update is never shown" do
    response = @lunch.response_for(person(:alpha_member))
    draft = response.start_submission!(person(:alpha_member))
    draft.update!(answers: draft.answers.merge("sandwich" => "Big John"))

    assert_equal "Slim 4", by_label(by_person(answers(:admin), "AlphaMember World"), "Sandwich")["answer"]
  end

  test "limit truncates" do
    result = answers(:admin, limit: 1)

    assert_equal 1, result.value["items"].size
    assert result.value["truncated"]
  end

  test "an unknown form is not found" do
    assert_equal "Not found", call_tool("form_answers", user: user(:admin), form_id: "nope").error
  end

  test "with the feature off the tool is neither listed nor callable" do
    with_feature(:forms, false) do
      assert_equal "Feature off", answers(:admin).error
      assert_not_includes Mcp.available_tools(mcp_context(user(:admin))).map(&:tool_name), "form_answers"
    end
  end
end
