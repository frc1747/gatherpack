require "test_helper"
require_relative "../../../support/mcp_world"

# get_person's contact details follow the built-in person fields' read rules
# and show_on_profile, as people/_fields renders them (filter registered in
# config/initializers/mcp_person_fields.rb).
class Mcp::Tools::GetPersonFilterTest < ActionDispatch::IntegrationTest
  include McpWorld
  include Devise::Test::IntegrationHelpers

  KEYS = Mcp::Tools::GetPerson::PROFILE_FIELD_KEYS

  setup do
    build_mcp_world
    PersonField.ensure_system_fields!
    @subject = person(:alpha_member)
    @subject.update!(phone_number: "555-0100", address: "1 Main St", birthday: Date.new(2012, 5, 6),
      dietary_restrictions: "Peanuts", shirt_size: "M", gender: "F")
  end

  def returned(viewer, target = :alpha_member)
    result = call_tool("get_person", user: user(viewer), person_id: person(target).neat_id)
    assert_not result.error?, result.error
    result.value.keys & KEYS
  end

  def field(source)
    PersonField.find_by!(system_source: source)
  end

  test "default privacy settings return every contact key" do
    assert_equal KEYS.sort, returned(:ward).sort
  end

  test "recommended privacy leaves a teammate email, shirt size and gender only" do
    PersonField.apply_recommended_privacy!
    assert_equal %w[email gender shirt_size], returned(:ward).sort
  end

  test "recommended privacy: the subject, a manager and an admin see their level" do
    PersonField.apply_recommended_privacy!
    assert_equal KEYS.sort, returned(:alpha_member).sort
    assert_equal KEYS.sort, returned(:alpha_manager).sort
    assert_equal KEYS.sort, returned(:admin).sort
  end

  test "a restricted field is left out for a viewer below its level, not nulled" do
    field("phone_number").update!(read_permission: :self_and_leaders, write_permission: :self_and_leaders)
    assert_not_includes returned(:ward), "phone_number"
    assert_includes returned(:alpha_member), "phone_number"
    assert_includes returned(:alpha_manager), "phone_number"
    assert_equal "555-0100", call_tool("get_person", user: user(:alpha_member), person_id: @subject.neat_id).value["phone_number"]
  end

  test "email follows user.email, not the field key" do
    field("user.email").update!(read_permission: :leaders)
    assert_not_includes returned(:ward), "email"
    assert_includes returned(:alpha_manager), "email"
  end

  test "a field off the profile is left out for a non-admin" do
    field("address").update!(show_on_profile: false)
    assert_not_includes returned(:ward), "address"
    assert_not_includes returned(:alpha_manager), "address"
  end

  test "an archived field is left out" do
    field("birthday").archive!
    assert_not_includes returned(:ward), "birthday"
  end

  test "with no built-in field rows nothing is returned, as the page shows nothing" do
    PersonField.system.update_all(archived_at: Time.current)
    assert_empty returned(:ward)
  end

  test "the filter applies with the person_fields flag off" do
    PersonField.apply_recommended_privacy!
    with_feature(:person_fields, false) do
      assert_equal %w[email gender shirt_size], returned(:ward).sort
      assert_not call_tool("get_person", user: user(:ward), person_id: @subject.neat_id).value.key?("fields")
    end
  end

  test "get_person matches the profile page for a teammate" do
    PersonField.apply_recommended_privacy!
    field("shirt_size").update!(show_on_profile: false)
    host! "localhost"
    sign_in user(:ward)
    get person_path(@subject)
    assert_response :success
    page = response.body
    shown = { "email" => "Email", "phone_number" => "Phone", "birthday" => "Birthday", "address" => "Address",
              "dietary_restrictions" => "Dietary Restrictions", "shirt_size" => "Shirt Size", "gender" => "Gender" }
    on_page = shown.select { |_, label| page.include?("<b>#{label}: </b>") }.keys
    assert_equal on_page.sort, returned(:ward).sort
    assert_equal %w[email gender], on_page.sort
  end
end
