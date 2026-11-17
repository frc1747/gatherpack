require "test_helper"
require_relative "../../support/intake_world"

class Intake::KioskQuestionsTest < ActionDispatch::IntegrationTest
  include IntakeWorld
  include ActiveJob::TestHelper
  include Devise::Test::IntegrationHelpers

  setup do
    host! "localhost"
    build_intake_world
    @school = PersonField.create!(name: "School", data_type: :string, read_permission: "self_and_leaders", write_permission: "self_and_leaders")
    @grade = PersonField.create!(name: "Grade", data_type: :integer, read_permission: "self_and_leaders", write_permission: "self_and_leaders", required: true)
    @registration.update!(kiosk: true, kiosk_field_ids: [ @school.id, @grade.id ])
    sign_in @leader.user
  end

  def kiosk_params(email: "jamie@example.com", answers: { @school.key => "Northwind High", @grade.key => "10" })
    { kiosk: { first_name: "Jamie", last_name: "Fox", birth_year: 1990, email: email, email_confirmation: email, team_ids: [ @mentors.id ] },
      person: { person_field_values: answers } }
  end

  test "the kiosk asks the registration's questions, blank" do
    with_intake(feature_person_fields: "true") { get intake_kiosk_path(@registration.slug) }

    assert_select "input[name='person[person_field_values][#{@school.key}]']"
    assert_select "input[name='person[person_field_values][#{@grade.key}]']"
  end

  test "answers are saved for someone new and kept on the entry" do
    with_intake(feature_person_fields: "true") { post intake_kiosk_path(@registration.slug), params: kiosk_params }

    jamie = User.find_by!(email: "jamie@example.com").person
    assert_equal "Northwind High", jamie.field_value(@school)
    assert_equal 10, jamie.field_value(@grade)
    assert_equal({ @school.key => "Northwind High", @grade.key => 10 }, Intake::Entry.sole.facts["answers"])
  end

  test "a required question must be answered, and answers must fit the field" do
    with_intake(feature_person_fields: "true") do
      post intake_kiosk_path(@registration.slug), params: kiosk_params(answers: { @school.key => "X" })
      assert_match "Grade can&#39;t be blank.", response.body
      post intake_kiosk_path(@registration.slug), params: kiosk_params(answers: { @grade.key => "tenth" })
      assert_match "Grade must be a whole number.", response.body
    end
    assert_empty Intake::Entry.all
  end

  test "someone already on file isn't changed from the kiosk" do
    existing = create_intake_person("Jamie", "Fox", email: "jamie@example.com")
    existing.set_field_value(@school, "Old School")

    with_intake(feature_person_fields: "true") { post intake_kiosk_path(@registration.slug), params: kiosk_params }

    assert_equal "Old School", existing.reload.field_value(@school)
    assert_equal "Northwind High", Intake::Entry.sole.facts["answers"][@school.key]
  end

  test "no questions while person fields are off" do
    with_intake { get intake_kiosk_path(@registration.slug) }

    assert_select "input[name^='person[person_field_values]']", 0
  end

  test "only custom person fields can be kiosk questions" do
    PersonField.ensure_system_fields!
    birthday = PersonField.find_by!(system_source: "birthday")

    assert_not @registration.update(kiosk_field_ids: [ birthday.id ])
    assert_includes @registration.errors[:kiosk_field_ids], "can only be custom person fields"
  end
end
