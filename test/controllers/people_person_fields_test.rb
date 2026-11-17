require "test_helper"
require_relative "../support/person_fields_world"
require_relative "../support/settings_test_helper"

class PeoplePersonFieldsTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers
  include PersonFieldsWorld
  include SettingsTestHelper

  setup do
    host! "localhost"
    build_person_fields_world
    @medical = PersonFieldGroup.create!(name: "Medical")
    @allergies = create_world_field("Food Allergies", read: "family", write: "family", person_field_group: @medical)
    @behavior = create_world_field("Behavior Notes", read: "guardians", write: "leaders")
    person(:a1).set_field_value(@allergies, "severe peanut allergy")
    person(:a1).set_field_value(@behavior, "needs a buddy")
  end

  test "the profile shows a restricted field only to people who can read it" do
    with_feature do
      as(:parent_a1) { get person_path(person(:a1)) }
      assert_includes response.body, "severe peanut allergy"
      assert_select "h5", text: "Medical"

      %i[ parent_a2 den_b_leader a2 b1 ].each do |viewer|
        as(viewer) { get person_path(person(:a1)) }
        # Some of these viewers can't open the profile at all.
        next assert_response(:not_found) if viewer == :parent_a2

        assert_response :success
        assert_not_includes response.body, "peanut", "#{viewer} saw the allergy"
        assert_not_includes response.body, "Food Allergies", "#{viewer} saw the field name"
        assert_not_includes response.body, "food_allergies", "#{viewer} saw the field key"
        assert_not_includes response.body, "Medical", "#{viewer} saw the section"
        assert_not_includes response.body, "Behavior Notes", "#{viewer} saw the field name"
      end
    end
  end

  test "the subject doesn't see a guardians-level field about themself" do
    with_feature do
      as(:a1) { get person_path(person(:a1)) }

      assert_includes response.body, "severe peanut allergy"
      assert_not_includes response.body, "needs a buddy"
    end
  end

  test "custom fields stay hidden while the feature is off" do
    as(:parent_a1) { get person_path(person(:a1)) }

    assert_not_includes response.body, "peanut"
  end

  test "a guardian can edit the fields they can write, and nothing else" do
    with_feature do
      as(:parent_a1) { get edit_person_path(person(:a1)) }
      assert_response :success
      assert_select "input[name='person[person_field_values][food_allergies]'][value='severe peanut allergy']"
      assert_select "input[name='person[first_name]']", count: 0
      assert_select "textarea[name='person[bio]']", count: 0
      assert_includes response.body, "A1 World can see and change this."

      as(:parent_a1) do
        patch person_path(person(:a1)), params: { person: {
          first_name: "Hacked", bio: "hacked",
          person_field_values: { food_allergies: "peanut and shellfish", behavior_notes: "hacked" }
        } }
      end
      assert_redirected_to person_path(person(:a1))

      a1 = person(:a1).reload
      assert_equal "peanut and shellfish", a1.field_value(@allergies)
      assert_equal "needs a buddy", a1.field_value(@behavior)
      assert_equal "A1", a1.first_name
      assert_nil a1.bio
    end
  end

  test "a guardian sees a guardians-level note on the edit form" do
    @behavior.update!(write_permission: "guardians")

    with_feature do
      as(:parent_a1) { get edit_person_path(person(:a1)) }

      assert_includes response.body, "Not visible to A1 World."
    end
  end

  test "someone who can't write any field can't reach the edit form" do
    with_feature do
      as(:den_b_leader) { get edit_person_path(person(:a1)) }
      assert_redirected_to root_path

      as(:den_b_leader) { patch person_path(person(:a1)), params: { person: { person_field_values: { food_allergies: "hacked" } } } }
      assert_equal "severe peanut allergy", person(:a1).reload.field_value(@allergies)
    end
  end

  test "a leader edits the base profile and fields together" do
    with_feature do
      as(:den_a_leader) do
        patch person_path(person(:a1)), params: { person: { first_name: "Ann", person_field_values: { food_allergies: "", behavior_notes: "doing well" } } }
      end

      a1 = person(:a1).reload
      assert_equal "Ann", a1.first_name
      assert_nil a1.field_value(@allergies)
      assert_equal "doing well", a1.field_value(@behavior)
    end
  end

  test "invalid field input re-renders the form with the error" do
    create_world_field("Troop Number", read: "everyone", write: "self_and_leaders", data_type: :integer)

    with_feature do
      as(:den_a_leader) { patch person_path(person(:a1)), params: { person: { person_field_values: { troop_number: "abc" } } } }

      assert_response :unprocessable_entity
      assert_includes response.body, "must be a whole number"
      assert_select "input[name='person[person_field_values][troop_number]'][value='abc']"
    end
  end

  test "field values are filtered from the logs" do
    filter = ActiveSupport::ParameterFilter.new(Rails.application.config.filter_parameters)

    assert_equal "[FILTERED]", filter.filter(person: { person_field_values: { food_allergies: "peanut" } })[:person][:person_field_values]
  end

  private

  def with_feature(&block)
    with_settings(feature_person_fields: "true", &block)
  end

  def as(name)
    sign_in person(name).user
    yield
  ensure
    sign_out :user
  end
end
