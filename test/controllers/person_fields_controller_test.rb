require "test_helper"
require_relative "../support/person_fields_world"
require_relative "../support/settings_test_helper"

class PersonFieldsControllerTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers
  include PersonFieldsWorld
  include SettingsTestHelper

  setup do
    host! "localhost"
    build_person_fields_world
    @allergies = create_world_field("Food Allergies", read: "family", write: "family")
    person(:a1).set_field_value(@allergies, "peanut")
    person(:b1).set_field_value(@allergies, "shellfish")
  end

  test "only admins can manage field definitions" do
    with_feature do
      as(:den_a_leader) do
        get person_fields_path
        assert_redirected_to root_path
        get edit_person_field_path(@allergies)
        assert_redirected_to root_path
        patch person_field_path(@allergies), params: { person_field: { read_permission: "everyone" } }
      end
      assert @allergies.reload.read_family?
    end
  end

  test "the index shows the access matrix" do
    @allergies.person_field_badge_grants.create!(badge: @health_officer_badge, access: :read)

    with_feature do
      as(:admin) { get person_fields_path }

      assert_response :success
      assert_select "tr#person_field_#{@allergies.id}" do
        assert_select "td", text: /This person, their guardians, and their leaders/
        assert_select ".badge", text: "Health Officer: see"
      end
      assert_select "a", text: "New Field"
    end
  end

  test "with the feature off, the index hides custom fields and new field" do
    as(:admin) { get person_fields_path }

    assert_response :success
    assert_select "tr#person_field_#{@allergies.id}", count: 0
    assert_select "a", text: "New Field", count: 0

    as(:admin) { get new_person_field_path }
    assert_redirected_to root_path
  end

  test "an admin creates a select field with badge access" do
    with_feature do
      as(:admin) do
        get new_person_field_path
        assert_response :success

        post person_fields_path, params: { person_field: {
          name: "T-Shirt Size", data_type: "select", choices_text: "S\nM\nL",
          read_permission: "team", write_permission: "self_and_leaders",
          badge_access: { @health_officer_badge.id => "write", @assistant_badge.id => "none" }
        } }
      end

      assert_redirected_to person_fields_path
      field = PersonField.find_by!(key: "t_shirt_size")
      assert_equal %w[ S M L ], field.choices
      assert_equal({ @health_officer_badge.id => "write" }, field.badge_access)
    end
  end

  test "badge access can be changed and removed from the form" do
    @allergies.person_field_badge_grants.create!(badge: @health_officer_badge, access: :read)

    with_feature do
      as(:admin) do
        patch person_field_path(@allergies), params: { person_field: { badge_access: { @health_officer_badge.id => "none", @assistant_badge.id => "read" } } }
      end

      assert_equal({ @assistant_badge.id => "read" }, @allergies.reload.badge_access)
    end
  end

  test "the containment error shows on the form" do
    with_feature do
      as(:admin) { patch person_field_path(@allergies), params: { person_field: { read_permission: "leaders", write_permission: "family" } } }

      assert_response :unprocessable_entity
      assert_includes response.body, "can&#39;t include people who can&#39;t see this field"
      assert @allergies.reload.read_family?
    end
  end

  test "the key and type are fixed once there are values" do
    with_feature do
      as(:admin) { patch person_field_path(@allergies), params: { person_field: { key: "renamed", data_type: "text" } } }

      @allergies.reload
      assert_equal "food_allergies", @allergies.key
      assert @allergies.type_string?
    end
  end

  test "archive, restore, and delete" do
    with_feature do
      as(:admin) do
        delete person_field_path(@allergies)
        assert_redirected_to root_path
        assert PersonField.exists?(@allergies.id)

        patch archive_person_field_path(@allergies)
        assert @allergies.reload.archived?
        assert_equal "peanut", person(:a1).field_value(@allergies)

        patch restore_person_field_path(@allergies)
        assert_not @allergies.reload.archived?

        patch archive_person_field_path(@allergies)
        get person_fields_path(archived: "1")
        assert_select "button[data-turbo-confirm*='2 values']"

        delete person_field_path(@allergies)
        assert_redirected_to person_fields_path(archived: "1")
      end

      assert_not PersonField.exists?(@allergies.id)
      assert_equal 0, PersonFieldValue.where(person_field_id: @allergies.id).count
    end
  end

  test "fields move within their section" do
    second = create_world_field("Second", read: "everyone")
    @allergies.update!(position: 0)
    second.update!(position: 1)

    with_feature do
      as(:admin) { patch move_person_field_path(second, direction: "up") }
    end

    assert_equal [ "Second", "Food Allergies" ], PersonField.ordered.map(&:name)
  end

  test "preview as shows what one person can see and why" do
    @allergies.person_field_badge_grants.create!(badge: @health_officer_badge, access: :read)
    create_world_field("Leader Notes", read: "leaders")

    with_feature do
      as(:admin) { get preview_person_fields_path(preview: { viewer_id: person(:health_officer).id, subject_id: person(:a1).id }) }

      assert_response :success
      assert_includes response.body, "Holds the Health Officer badge"
      assert_includes response.body, "peanut"

      as(:admin) { get preview_person_fields_path(preview: { viewer_id: person(:pack_leader).id, subject_id: person(:a1).id }) }
      assert_includes response.body, "Leader of Pack"
    end
  end

  test "preview is for admins only" do
    as(:den_a_leader) { get preview_person_fields_path }

    assert_redirected_to root_path
  end

  test "the roster shows each person's value only to those who can read it" do
    @allergies.person_field_badge_grants.create!(badge: @health_officer_badge, access: :read)

    with_feature do
      as(:den_a_leader) { get roster_person_fields_path(field_ids: [ @allergies.id ]) }
      assert_includes response.body, "peanut"
      assert_not_includes response.body, "shellfish"

      as(:parent_a1) { get roster_person_fields_path(field_ids: [ @allergies.id ]) }
      assert_includes response.body, "peanut"
      assert_not_includes response.body, "shellfish"
      assert_not_includes response.body, "B1 World"

      as(:health_officer) { get roster_person_fields_path(field_ids: [ @allergies.id ]) }
      assert_includes response.body, "shellfish"

      as(:den_b_leader) { get roster_person_fields_path(field_ids: [ @allergies.id ]) }
      assert_includes response.body, "shellfish"
      assert_not_includes response.body, "peanut"

      as(:a2) { get roster_person_fields_path(field_ids: [ @allergies.id ]) }
      assert_includes response.body, "A2 World"
      assert_not_includes response.body, "peanut"
    end
  end

  test "the roster says so when there is nothing to show" do
    @allergies.archive!
    create_world_field("Leader Notes", read: "leaders")

    with_feature do
      as(:a2) { get roster_person_fields_path }
    end

    assert_response :success
    assert_includes response.body, "There are no fields you can view for anyone."
  end

  test "the roster can be narrowed to a team" do
    with_feature do
      as(:pack_leader) { get roster_person_fields_path(field_ids: [ @allergies.id ], team_id: @den_b.id) }
    end

    assert_includes response.body, "shellfish"
    assert_not_includes response.body, "peanut"
  end

  test "the roster and its nav link follow the feature flag" do
    as(:den_a_leader) { get roster_person_fields_path }
    assert_redirected_to root_path

    with_feature do
      as(:den_a_leader) { get person_path(person(:den_a_leader)) }
      assert_select "a[href='#{roster_person_fields_path}']", text: /Member Info/
    end
  end

  test "sections can be created, reordered, and deleted" do
    with_feature do
      as(:admin) do
        post person_field_groups_path, params: { person_field_group: { name: "Medical", position: 0 } }
        post person_field_groups_path, params: { person_field_group: { name: "Contact", position: 1 } }
        contact = PersonFieldGroup.find_by!(name: "Contact")
        patch move_person_field_group_path(contact, direction: "up")
        assert_equal %w[ Contact Medical ], PersonFieldGroup.ordered.map(&:name)

        get person_field_groups_path
        assert_response :success

        medical = PersonFieldGroup.find_by!(name: "Medical")
        @allergies.update!(person_field_group: medical)
        delete person_field_group_path(medical)
      end

      assert_nil @allergies.reload.person_field_group
    end
  end

  test "only admins can manage sections" do
    as(:den_a_leader) { post person_field_groups_path, params: { person_field_group: { name: "Medical" } } }

    assert_not PersonFieldGroup.exists?(name: "Medical")
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
