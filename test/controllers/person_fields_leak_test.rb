require "test_helper"
require_relative "../support/person_fields_world"

# Spec section 11.2 and 11.8: built-in details under person field control,
# before and after "Apply recommended privacy settings".
class PersonFieldsLeakTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers
  include PersonFieldsWorld

  setup do
    host! "localhost"
    build_person_fields_world
    PersonField.ensure_system_fields!
    person(:a1).update!(dietary_restrictions: "peanut allergy", phone_number: "555-0199", birthday: Date.new(2015, 6, 15), gender: "F", shirt_size: "Youth M")
  end

  test "upgrading changes nothing a teammate can see" do
    as(:a2) { get person_path(person(:a1)) }

    assert_includes response.body, "peanut allergy"
    assert_includes response.body, "555-0199"
    assert_includes response.body, "June 15, 2015"
    assert_includes response.body, "a1@example.com"
    assert_select "h5", text: "Contact"
  end

  test "ensuring system fields again keeps an admin's changes" do
    dietary = PersonField.find_by!(system_source: "dietary_restrictions")
    dietary.update!(read_permission: "family", write_permission: "family", name: "Allergies")

    assert_no_difference -> { PersonField.count } do
      PersonField.ensure_system_fields!
    end
    assert dietary.reload.read_family?
    assert_equal "Allergies", dietary.name
  end

  test "existing relationship types grant no guardianship after upgrading" do
    assert relationship_types(:one).guardianship_none?
  end

  test "applying the recommended settings restricts the details everywhere" do
    PersonField.apply_recommended_privacy!

    as(:den_b_leader) { get person_path(person(:a1)) }
    assert_response :success
    assert_not_includes response.body, "peanut"
    assert_not_includes response.body, "555-0199"
    assert_not_includes response.body, "June 15, 2015"
    assert_not_includes response.body, "Dietary Restrictions"

    as(:a2) { get person_path(person(:a1)) }
    assert_includes response.body, "Youth M"
    assert_includes response.body, "a1@example.com"
    assert_not_includes response.body, "peanut"

    as(:parent_a1) { get person_path(person(:a1)) }
    assert_includes response.body, "peanut allergy"
    assert_includes response.body, "555-0199"
  end

  test "the recommended settings let guardians edit every detail but email" do
    PersonField.apply_recommended_privacy!
    a1 = person(:a1)

    %w[ phone_number address birthday dietary_restrictions shirt_size gender ].each do |source|
      field = PersonField.find_by!(system_source: source)
      assert field.writable_by?(person(:parent_a1), a1), "guardian can't edit #{source}"
      assert field.writable_by?(a1, a1), "the person can't edit #{source}"
      assert field.writable_by?(person(:den_a_leader), a1), "a leader can't edit #{source}"
      assert_not field.writable_by?(person(:a2), a1), "a teammate can edit #{source}"
    end
    assert_not PersonField.find_by!(system_source: "user.email").writable_by?(person(:parent_a1), a1)
    assert PersonField.find_by!(system_source: "shirt_size").readable_by?(person(:a2), a1)
    assert_not PersonField.find_by!(system_source: "phone_number").readable_by?(person(:a2), a1)
  end

  test "restricted details don't leak through search, sorting, the calendar, combo search, or the API" do
    PersonField.apply_recommended_privacy!

    as(:den_b_leader) do
      get people_path, params: { q: { dietary_restrictions_cont: "peanut" } }
      assert_includes response.body, "B1 World", "the restricted filter should be ignored"

      get people_path
      assert_select "a", text: "Age", count: 0

      get "/calendar/calendar.json", params: calendar_params
      assert_not_includes response.body, "A1 World's Birthday"

      get combo_search_path(q: "A1", scope: "people", format: :turbo_stream)
      assert_response :success
      assert_includes response.body, "A1 World"
      assert_not_includes response.body, "peanut"
      assert_not_includes response.body, "555-0199"

      get audit_logs_path
      assert_redirected_to root_path
    end

    as(:parent_a1) { get "/calendar/calendar.json", params: calendar_params }
    assert_includes response.body, "A1 World's Birthday"
  end

  test "the userinfo API carries no person field values" do
    app = Doorkeeper::Application.create!(name: "Test App", redirect_uri: "https://example.com/callback", scopes: "user_read")
    token = Doorkeeper::AccessToken.create!(resource_owner_id: person(:a1).user.id, application_id: app.id,
      scopes: "user_read user_email user_name teams_read badges_read", expires_in: 2.hours)

    get "/api/v1/userinfo", headers: { Authorization: "Bearer #{token.plaintext_token}" }

    assert_response :success
    %w[ peanut 555-0199 2015-06-15 Youth ].each { |value| assert_not_includes response.body, value }
  end

  test "people edit built-in details through the field form" do
    as(:a1) do
      get edit_person_path(person(:a1))
      assert_select "input[name='person[person_field_values][phone]'][value='555-0199']"
      assert_select "select[name='person[person_field_values][shirt_size]'] option[selected]", text: "Youth M"
      assert_select "input[name='person[phone_number]']", count: 0

      patch person_path(person(:a1)), params: { person: { person_field_values: { phone: "555-0123", shirt_size: "Youth L", birthday: "2015-06-15" } } }
    end

    a1 = person(:a1).reload
    assert_equal "555-0123", a1.phone_number
    assert_equal "Youth L", a1.shirt_size
  end

  test "the old column parameters no longer write anything" do
    as(:a1) { patch person_path(person(:a1)), params: { person: { phone_number: "555-0000", dietary_restrictions: "none" } } }

    assert_equal "555-0199", person(:a1).reload.phone_number
    assert_equal "peanut allergy", person(:a1).dietary_restrictions
  end

  test "a legacy value that wouldn't pass validation doesn't block saving" do
    person(:a1).update_columns(phone_number: "call the office")

    as(:a1) { patch person_path(person(:a1)), params: { person: { first_name: "Ann", person_field_values: { phone: "call the office" } } } }

    assert_equal "Ann", person(:a1).reload.first_name
  end

  test "email is shown but can't be changed through the profile" do
    as(:admin) { patch person_path(person(:a1)), params: { person: { person_field_values: { email: "new@example.com" } } } }
    assert_equal "a1@example.com", person(:a1).user.reload.email

    no_account = Person.create!(first_name: "No", last_name: "Account")
    Membership.create!(person: no_account, team: @den_a)
    as(:a2) { get person_path(no_account) }
    assert_includes response.body, "No account attached."
  end

  test "only admins can apply the recommended settings, and each change is audited" do
    as(:den_a_leader) { post apply_recommended_person_fields_path }
    assert PersonField.find_by!(system_source: "dietary_restrictions").read_everyone?

    as(:admin) do
      get person_fields_path
      assert_select "button", text: "Apply recommended privacy settings"

      assert_difference -> { AuditLog.where(item_type: "PersonField").count }, 7 do
        post apply_recommended_person_fields_path
      end
      assert_redirected_to person_fields_path

      get person_fields_path
      assert_select "button", text: "Apply recommended privacy settings", count: 0
    end
    assert PersonField.find_by!(system_source: "dietary_restrictions").read_family?
    assert PersonField.find_by!(system_source: "user.email").read_team?
  end

  test "system fields can't be deleted or have their type changed" do
    phone = PersonField.find_by!(system_source: "phone_number")
    phone.archive!

    assert_not phone.destroy
    assert_not phone.update(data_type: "string")
    assert_not phone.update(team: @den_a)
  end

  private

  def calendar_params
    { birthdays: "1", start_time: Date.current.beginning_of_year.iso8601, end_time: Date.current.end_of_year.iso8601, q: { name_i_cont: "" } }
  end

  def as(name)
    sign_in person(name).user
    yield
  ensure
    sign_out :user
  end
end
