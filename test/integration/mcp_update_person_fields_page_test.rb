require "test_helper"
require_relative "../support/mcp_world"

# update_person_fields against the real edit page: the same input from the same viewer
# stores the same thing, or nothing on both sides. The page silently drops a key the
# viewer can't write and saves the rest; the tool refuses the whole call and names the
# keys, which is the one place they differ and is tested as such.
class McpUpdatePersonFieldsPageTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers
  include McpWorld

  setup do
    host! "localhost"
    build_mcp_world
    @restore_person_fields = apply_settings(feature_person_fields: "true")
    PersonField.ensure_system_fields!
    @subject = person(:alpha_member)
    @subject.update!(birthday: Date.new(1980, 1, 1), phone_number: "555-0100", address: "1 Main St")
    @notes = PersonField.create!(name: "Notes", data_type: :text, read_permission: :leaders, write_permission: :leaders)
    @nickname = PersonField.create!(name: "Nickname", data_type: :string, read_permission: :everyone, write_permission: :self)
    @eligible = PersonField.create!(name: "Eligible", data_type: :boolean, read_permission: :everyone, write_permission: :admin)
    @size = PersonField.create!(name: "Jacket", data_type: :select, choices_text: "S\nM", read_permission: :everyone, write_permission: :self)
    @many = PersonField.create!(name: "Sports", data_type: :multi_select, choices_text: "Golf\nTennis", read_permission: :everyone, write_permission: :self)
  end

  teardown { @restore_person_fields&.call }

  def snapshot
    person = Person.find(@subject.id)
    [ @notes, @nickname, @eligible, @size, @many ].map { |field| person.field_value(field) } + [ person.phone_number, person.address, person.birthday ]
  end

  def reset
    person = Person.find(@subject.id)
    [ @notes, @nickname, @eligible, @size, @many ].each { |field| person.set_field_value(field, nil) }
    person.update!(phone_number: "555-0100", address: "1 Main St", birthday: Date.new(1980, 1, 1))
  end

  def by_page(viewer, form)
    reset
    sign_in viewer
    patch person_path(@subject), params: { person: { person_field_values: form } }
    sign_out viewer
    snapshot
  end

  def by_tool(viewer, values)
    reset
    call_tool("update_person_fields", user: viewer, person_id: @subject.neat_id, values: values)
    snapshot
  end

  test "values every viewer may write are stored the same by the page and the tool" do
    form = { "nickname" => "Sam", "jacket" => "M", "sports" => %w[Golf Tennis] }
    values = { "nickname" => "Sam", "jacket" => "M", "sports" => %w[Golf Tennis] }

    [ user(:admin), user(:alpha_member) ].each do |viewer|
      page = by_page(viewer, form)
      tool = by_tool(viewer, values)
      assert_equal page, tool, viewer.email
      assert_equal "Sam", tool[1]
    end
  end

  test "built-in and typed values, from the viewers who may write them" do
    form = { "notes" => "Quiet", "eligible" => "1", "phone" => "555-0199", "address" => "2 Elm St", "birthday" => "1981-02-03" }
    values = { "notes" => "Quiet", "eligible" => true, "phone" => "555-0199", "address" => "2 Elm St", "birthday" => "1981-02-03" }

    [ user(:admin), user(:alpha_manager) ].each do |viewer|
      page = by_page(viewer, form)
      tool = by_tool(viewer, values.slice(*writable_keys(viewer, values.keys)))
      assert_equal page, tool, viewer.email
    end
  end

  test "an empty value clears a field on the page and null clears it through the tool" do
    %w[notes phone].each do |key|
      prepare = lambda do
        reset
        Person.find(@subject.id).update!(phone_number: "555-0100")
        Person.find(@subject.id).set_field_value(@notes, "Old")
      end
      prepare.call
      sign_in user(:admin)
      patch person_path(@subject), params: { person: { person_field_values: { key => "" } } }
      sign_out user(:admin)
      page = snapshot
      prepare.call
      call_tool("update_person_fields", user: user(:admin), person_id: @subject.neat_id, values: { key => nil })

      assert_equal page, snapshot, key
      assert_nil snapshot[key == "notes" ? 0 : 5], key
    end
  end

  test "a value the page refuses is refused by the tool, and neither stores any of the call" do
    [ { "nickname" => "Sam", "jacket" => "XL" }, { "nickname" => "Sam", "sports" => [ "Chess" ] }, { "nickname" => "Sam", "birthday" => "someday" } ].each do |form|
      before = by_page(user(:admin), {})
      page = by_page(user(:admin), form)
      assert_equal before, page, form.inspect

      assert_equal before, by_tool(user(:admin), form), form.inspect
      assert call_tool("update_person_fields", user: user(:admin), person_id: @subject.neat_id, values: form).error?
    end
  end

  test "a required field left blank is refused on both sides" do
    PersonField.create!(name: "Must Have", data_type: :string, read_permission: :everyone, write_permission: :admin, required: true)

    assert_equal by_page(user(:admin), {}), by_page(user(:admin), { "nickname" => "Sam" })
    assert_equal by_page(user(:admin), {}), by_tool(user(:admin), { "nickname" => "Sam" })
  end

  test "a key the viewer can't write: the page drops it, the tool refuses the call by name" do
    form = { "nickname" => "Sam", "eligible" => "1" }

    page = by_page(user(:alpha_member), form)
    assert_equal "Sam", page[1]
    assert_equal false, page[2]

    reset
    result = call_tool("update_person_fields", user: user(:alpha_member), person_id: @subject.neat_id, values: { "nickname" => "Sam", "eligible" => true })
    assert_equal "Not allowed: eligible", result.error
    assert_equal [ nil, nil, false, nil, nil ], snapshot.first(5)
  end

  test "a viewer the page can't reach is refused on both sides" do
    sign_in user(:beta_member)
    get edit_person_path(@subject)
    assert_response :not_found
    sign_out user(:beta_member)

    assert_equal "Not found", call_tool("update_person_fields", user: user(:beta_member), person_id: @subject.neat_id, values: { "nickname" => "x" }).error
  end

  test "the values stay out of the request log, whether the call is allowed or refused" do
    [ user(:admin), user(:alpha_member) ].each do |viewer|
      logged = +""
      subscriber = ->(*, payload) { logged << payload[:params].to_s if payload[:controller] == "McpController" }
      with_settings(mcp_write_enabled: "true") do
        ActiveSupport::Notifications.subscribed(subscriber, "process_action.action_controller") do
          mcp_post(mcp_token(viewer, scopes: "mcp_write"), "tools/call",
            { name: "update_person_fields", arguments: { person_id: @subject.neat_id, values: { "notes" => "555-867-5309", "nickname" => "Hidden Nick" } } })
          # Undeclared arguments are refused only after Rails has logged them.
          [ { phone: "555-867-5309" }, { fields: { phone: "555-867-5309" } }, { field_values: { notes: "555-867-5309" } }, { changes: { notes: "555-867-5309" } } ].each do |extra|
            mcp_post(mcp_token(viewer, scopes: "mcp_write"), "tools/call",
              { name: "update_person_fields", arguments: { person_id: @subject.neat_id }.merge(extra) })
          end
        end
      end

      assert_response :success
      assert_includes logged, @subject.neat_id
      assert_not_includes logged, "555-867-5309"
      assert_not_includes logged, "Hidden Nick"
    end
  end

  private

  # The keys of values this viewer may write on the subject (the page would drop the others).
  def writable_keys(viewer, keys)
    writable = Person.find(@subject.id).writable_fields_for(viewer.person).map(&:key)
    keys & writable
  end
end
