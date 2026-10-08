require "test_helper"
require_relative "../support/forms_world"
require_relative "../support/settings_test_helper"

class FormAccessTest < ActiveSupport::TestCase
  include FormsWorld
  include SettingsTestHelper

  AUDIENCE = %i[ a1 a2 b1 den_a_leader den_b_leader pack_leader assistant ].freeze

  setup do
    build_person_fields_world
  end

  test "the audience is the form's team and every team below it" do
    form = create_world_form
    assert_equal AUDIENCE.map { |name| person(name).id }.sort, form.audience.ids.sort
  end

  test "an audience badge narrows the audience" do
    form = create_world_form(audience_badge: @assistant_badge)
    assert_equal [ person(:assistant).id ], form.audience.ids
  end

  test "who can respond for A1 at each level" do
    expected = {
      "self" => %i[ a1 ],
      "self_and_leaders" => %i[ a1 den_a_leader pack_leader ],
      "guardians" => %i[ parent_a1 den_a_leader pack_leader ],
      "family" => %i[ a1 parent_a1 den_a_leader pack_leader ],
      "team" => %i[ a1 a2 parent_a1 den_a_leader pack_leader assistant ]
    }
    expected.each do |level, allowed|
      form = create_world_form("Respond #{level}", respond: level, read: level == "guardians" ? "guardians" : "team")
      PersonFieldsWorld::PEOPLE.each do |viewer|
        assert_equal viewer == :admin || allowed.include?(viewer), FormAccess.new(person(viewer), person(:a1), form).can_respond?,
          "#{viewer} responding for A1 at #{level}"
      end
    end
  end

  test "nobody responds for someone outside the audience" do
    form = create_world_form(respond: "family")
    assert_not FormAccess.new(person(:parent_a1), person(:parent_a1), form).can_respond?
    assert_not FormAccess.new(person(:admin), person(:outsider), form).can_read?
  end

  test "the list form agrees with FormAccess for every viewer and subject" do
    %w[ self leaders self_and_leaders guardians family team everyone ].each do |level|
      form = create_world_form("Read #{level}", respond: "admin", read: level)
      PersonFieldsWorld::PEOPLE.each do |viewer|
        expected = PersonFieldsWorld::PEOPLE.select { |subject| FormAccess.new(person(viewer), person(subject), form).can_read? }.map { |name| person(name).id }
        assert_equal expected.sort, form.readable_subjects_for(person(viewer)).ids.sort, "#{viewer} reading at #{level}"
      end
    end
  end

  test "respond must be within read" do
    form = Form.new(title: "Bad", team: @pack, respond_permission: "family", read_permission: "self_and_leaders")
    assert_not form.valid?
    assert form.errors.key?(:respond_permission)
  end

  test "a question can be more private than its form, never more public" do
    form = create_world_form(respond: "family", read: "family")
    private_question = add_choice(form, "Leader notes", %w[ Fine Watch ], read_permission: "leaders", write_permission: "leaders")
    assert private_question.persisted?

    public_question = form.form_questions.build(kind: :input, label: "Shirt", data_type: :string, read_permission: "team")
    assert_not public_question.valid?
    assert public_question.errors.key?(:read_permission)

    a1_access = FormAccess.new(person(:a1), person(:a1), form)
    leader_access = FormAccess.new(person(:den_a_leader), person(:a1), form)
    assert_not a1_access.question_readable?(private_question)
    assert leader_access.question_writable?(private_question)
  end

  test "a student-only part: guardians see it but only the student answers" do
    form = create_world_form(respond: "family", read: "family")
    question = form.form_questions.create!(kind: :input, label: "Code of conduct read", data_type: :boolean, write_permission: "self")

    assert FormAccess.new(person(:a1), person(:a1), form).question_writable?(question)
    parent = FormAccess.new(person(:parent_a1), person(:a1), form)
    assert parent.question_readable?(question)
    assert_not parent.question_writable?(question)
  end

  test "profile-backed questions also follow the person field's levels" do
    with_settings(feature_person_fields: "true") do
      notes = create_world_field("Leader Notes", read: "leaders", write: "leaders")
      form = create_world_form(respond: "family", read: "family")
      prefill = add_profile_question(form, notes, :prefill)

      parent = FormAccess.new(person(:parent_a1), person(:a1), form)
      assert parent.can_respond?
      assert_not parent.question_readable?(prefill), "the form can't widen who sees the profile field"
      assert FormAccess.new(person(:den_a_leader), person(:a1), form).question_writable?(prefill)
    end
  end

  test "updating the profile also needs write access to the field" do
    with_settings(feature_person_fields: "true") do
      allergies = create_world_field("Food Allergies", read: "family", write: "leaders")
      form = create_world_form(respond: "family", read: "family")
      prefill = add_profile_question(form, allergies, :prefill, key: "allergies_note")
      update = add_profile_question(form, allergies, :update_profile, key: "allergies")

      parent = FormAccess.new(person(:parent_a1), person(:a1), form)
      assert parent.question_writable?(prefill), "prefill only changes the form"
      assert_not parent.question_writable?(update), "updating the profile needs the field's write level"
      assert FormAccess.new(person(:den_a_leader), person(:a1), form).question_writable?(update)
    end
  end

  test "closed forms accept late entries from leaders only" do
    form = create_world_form(status: :closed, late_entry: "leaders")
    assert_not FormAccess.new(person(:parent_a1), person(:a1), form).can_submit?
    assert FormAccess.new(person(:den_a_leader), person(:a1), form).can_submit?

    form.update!(late_entry: "none")
    assert_not FormAccess.new(person(:den_a_leader), person(:a1), form).can_submit?
  end

  test "updates after submitting can be turned off, except for leaders" do
    form = create_world_form(allow_updates: false)
    assert_not FormAccess.new(person(:a1), person(:a1), form).can_update?
    assert FormAccess.new(person(:den_a_leader), person(:a1), form).can_update?
  end
end
