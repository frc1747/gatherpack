require "test_helper"

class QuestionsControllerTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers

  setup do
    host! "localhost"

    # Org (run by @org_leader)
    # ├── Team A (run by @lead_a, with @student_a)
    # └── Team B
    # Other Org
    @org = Team.create!(name: "Org", team_type: team_types(:one))
    @team_a = Team.create!(name: "Team A", team_type: team_types(:one), parent: @org)
    @team_b = Team.create!(name: "Team B", team_type: team_types(:one), parent: @org)
    @other_org = Team.create!(name: "Other Org", team_type: team_types(:one))

    @admin_user, = create_person("admin", admin: true)
    @lead_a_user, = create_person("lead-a", team: @team_a, manager: true)
    @org_leader_user, = create_person("org-leader", team: @org, manager: true)
    @student_a_user, student_a = create_person("student-a", team: @team_a)

    @question = Question.create!(title: "Q", content: "c", team: @team_a, person: student_a)
  end

  # --- move ---------------------------------------------------------------

  test "a manager cannot move a question to a team they don't manage" do
    sign_in @lead_a_user

    post move_question_path(@question), params: { team_id: @other_org.id }

    assert_equal @team_a.id, @question.reload.team_id, "Team A's manager moved a question into another organisation"
    assert_redirected_to root_path
  end

  test "a manager can move a question between teams they manage" do
    sign_in @org_leader_user

    post move_question_path(@question), params: { team_id: @team_b.id }

    assert_redirected_to question_path(@question)
    assert_equal @team_b.id, @question.reload.team_id
  end

  test "an admin can move a question to any team" do
    sign_in @admin_user

    post move_question_path(@question), params: { team_id: @other_org.id }

    assert_equal @other_org.id, @question.reload.team_id
  end

  # --- update -------------------------------------------------------------

  test "an author cannot move their question to a team they aren't in" do
    sign_in @student_a_user

    patch question_path(@question), params: { question: { team_id: @team_b.id } }

    assert_equal @team_a.id, @question.reload.team_id, "a student moved their question into Team B via update"
    assert_redirected_to root_path
  end

  test "an author can edit their question's text" do
    sign_in @student_a_user

    patch question_path(@question), params: { question: { title: "Better title", content: "More detail" } }

    assert_redirected_to question_path(@question)
    assert_equal "Better title", @question.reload.title
  end

  test "a manager cannot move a question through update to a team they don't manage" do
    sign_in @lead_a_user

    patch question_path(@question), params: { question: { team_id: @team_b.id } }

    assert_equal @team_a.id, @question.reload.team_id
  end

  test "a manager can move a question through update between teams they manage" do
    sign_in @org_leader_user

    patch question_path(@question), params: { question: { team_id: @team_b.id } }

    assert_equal @team_b.id, @question.reload.team_id
  end

  test "an admin can move a question through update to any team" do
    sign_in @admin_user

    patch question_path(@question), params: { question: { team_id: @other_org.id } }

    assert_equal @other_org.id, @question.reload.team_id
  end

  private

  def create_person(name, team: nil, manager: false, admin: false)
    user = User.create!(email: "#{name}@example.com", password: "Password1!", admin: admin)
    person = Person.create!(user: user, first_name: name.capitalize, last_name: "Test")
    Membership.create!(person: person, team: team, manager: manager) if team
    [ user, person ]
  end
end
