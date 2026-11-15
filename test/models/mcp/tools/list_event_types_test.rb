require "test_helper"
require_relative "../../../support/mcp_world"

class Mcp::Tools::ListEventTypesTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers
  include McpWorld

  setup do
    host! "localhost"
    build_mcp_world
  end

  def list_types(viewer, **options)
    call_tool("list_event_types", user: user(viewer), **options)
  end

  test "an admin and a team manager with no events get every type, by name" do
    expected = EventType.order(:name, :id).map { |type| { "id" => type.neat_id, "name" => type.name } }

    assert_equal expected, list_types(:admin).value["items"]
    assert_equal expected, list_types(:alpha_manager).value["items"]
  end

  test "a plain member and a guardian are refused" do
    assert_equal "Not allowed", list_types(:beta_member).error
    assert_equal "Not allowed", list_types(:guardian).error
  end

  test "limit truncates" do
    EventType.create!(name: "Another")
    value = list_types(:admin, limit: 1).value

    assert_equal 1, value["items"].size
    assert_equal true, value["truncated"]
  end

  test "it is off with the events feature" do
    with_feature(:events, false) { assert_equal "Feature off", list_types(:admin).error }
  end

  test "a listed type works in create_event" do
    type_id = list_types(:alpha_manager).value["items"].first["id"]
    result = call_tool("create_event", user: user(:alpha_manager), team_id: @alpha.neat_id, event_type_id: type_id,
      name: "Planning", starts_at: "2026-03-10T18:00:00", ends_at: "2026-03-10T19:00:00")

    assert_nil result.error
  end

  test "it refuses whoever the new event form refuses" do
    %i[admin alpha_manager alpha_member beta_member guardian].each do |viewer|
      sign_in user(viewer)
      get new_event_path
      page = response.successful?
      sign_out user(viewer)

      assert_equal page, !list_types(viewer).error?, viewer
    end
  end
end
