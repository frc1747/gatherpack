require "test_helper"
require_relative "../../../support/mcp_world"

class Mcp::Tools::UpdatePersonTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers
  include McpWorld

  setup do
    host! "localhost"
    build_mcp_world
    @saved_filters = Mcp.person_filters.dup
  end

  teardown { Mcp.person_filters.replace(@saved_filters) }

  def update(viewer, target, **attributes)
    call_tool("update_person", user: user(viewer), person_id: person(target).neat_id, **attributes)
  end

  def assert_unchanged(error, target)
    subject = person(target)
    before = subject.reload.attributes
    login = subject.user&.reload&.attributes
    audit_rows = AuditLog.count
    result = yield
    error.is_a?(Regexp) ? assert_match(error, result.error.to_s) : assert_equal(error, result.error)
    assert_nil result.changed
    assert_empty result.changed_records
    assert_equal before, subject.reload.attributes
    login ? assert_equal(login, subject.user.reload.attributes) : assert_nil(subject.user)
    assert_equal audit_rows, AuditLog.count
  end

  test "an admin changes the given attributes only, and gets the person as get_person shows them" do
    person(:ward).update!(bio: "Keeps this", display_name: "Wardy")
    result = update(:admin, :ward, first_name: "Changed")

    ward = person(:ward).reload
    assert_equal "Changed", ward.first_name
    assert_equal "World", ward.last_name
    assert_equal "Keeps this", ward.bio
    assert_equal "Wardy", ward.display_name
    assert_equal ward, result.changed
    assert_equal [ ward ], result.changed_records
    assert_equal call_tool("get_person", user: user(:admin), person_id: ward.neat_id).value, result.value
  end

  test "an empty string clears, and a blank display name resets, as on the page" do
    person(:ward).update!(bio: "Old", display_name: "Wardy")

    result = update(:admin, :ward, bio: "", display_name: "")

    assert_equal "", person(:ward).reload.bio
    assert_equal "Ward World", result.value["name"]
  end

  test "a bio takes line breaks, single-line attributes don't" do
    assert_not update(:admin, :ward, bio: "two\nlines").error?
    assert_unchanged(/first_name.*control characters/, :ward) { update(:admin, :ward, first_name: "a\nb") }
    assert_unchanged(/display_name.*control characters/, :ward) { update(:admin, :ward, display_name: "a\u0007b") }
  end

  test "a team manager changes their team's people and themselves, not others" do
    assert_not update(:alpha_manager, :alpha_member, last_name: "Changed").error?
    assert_not update(:alpha_manager, :alpha_manager, last_name: "Changed").error?
    assert_unchanged("Not found", :beta_member) { update(:alpha_manager, :beta_member, last_name: "Changed") }
  end

  test "a member changes themselves, not a teammate or someone on another team" do
    assert_not update(:alpha_member, :alpha_member, bio: "Me").error?
    assert_unchanged("Not allowed", :ward) { update(:alpha_member, :ward, bio: "Not me") }
    assert_unchanged("Not found", :alpha_member) { update(:beta_member, :alpha_member, bio: "Not me") }
  end

  test "a guardian can't change their ward's base profile" do
    assert_unchanged(/\ANot (found|allowed)/, :ward) { update(:guardian, :ward, first_name: "Changed") }
  end

  test "nothing to change is refused, and so are bad IDs and types" do
    assert_unchanged(/at least one/, :ward) { update(:admin, :ward) }
    [ "nonsense", "per_nonsense", @alpha.neat_id ].each do |bad|
      assert_refused("Not found", Person) { call_tool("update_person", user: user(:admin), person_id: bad, bio: "x") }
    end
    assert_unchanged(/.+/, :ward) { update(:admin, :ward, first_name: 7) }
    assert_unchanged(/.+/, :ward) { update(:admin, :ward, first_name: nil) }
    assert_refused(/person_id/, Person) { call_tool("update_person", user: user(:admin), bio: "x") }
  end

  test "email is refused by name for everyone, whatever else is sent, with the same answer for adults and minors" do
    person(:ward).update!(birthday: 30.years.ago.to_date)
    person(:alpha_member).update!(birthday: 10.years.ago.to_date)
    login_less = Person.create!(first_name: "No", last_name: "Login")
    Membership.create!(person: login_less, team: @alpha)
    @people[:login_less] = login_less

    answers = [ :ward, :alpha_member, :badge_holder, :login_less ].map do |target|
      assert_unchanged(/\ANot allowed: email/, target) { update(:admin, target, email: "changed@example.com", first_name: "Changed") }
      McpToolCall.order(:created_at).last.error_message
    end
    assert_equal 1, answers.uniq.size
    assert_equal "denied", McpToolCall.order(:created_at).last.outcome
  end

  test "someone who can't update the person learns nothing about email" do
    assert_unchanged("Not allowed", :ward) { update(:alpha_member, :ward, email: "changed@example.com") }
    assert_unchanged("Not found", :ward) { update(:beta_member, :ward, email: "changed@example.com") }
  end

  # Without person fields, the page takes these directly; with them, a connector's
  # tool does, applying write levels and the minors rule. Either way this isn't the way
  # in, and a filter hiding them changes nothing.
  test "contact details aren't taken, for a person-fields build's withheld keys or otherwise" do
    Mcp.person_filters << ->(_person, _viewer) { [] }
    person(:ward).update!(birthday: 30.years.ago.to_date, phone_number: "555-0100", address: "1 Old St")
    %i[phone_number address birthday gender shirt_size dietary_restrictions avatar user_id team_ids badge_ids].each do |key|
      assert_unchanged(/#{key}/, :ward) { update(:admin, :ward, key => "x", first_name: "Changed") }
    end
    assert_unchanged(/\ANot allowed: email/, :ward) { update(:admin, :ward, email: "changed@example.com") }
  end

  test "the result leaves out what a person filter leaves out" do
    Mcp.person_filters << ->(_person, _viewer) { [] }
    person(:ward).update!(birthday: 30.years.ago.to_date, phone_number: "555-0100")

    result = update(:admin, :ward, first_name: "Changed")

    assert_not result.value.key?("phone_number")
    assert_not result.value.key?("email")
    assert_equal "Changed", result.value["first_name"]
  end

  test "a minor's name and bio can still be changed, and their contact details stay out of the result" do
    person(:ward).update!(birthday: 10.years.ago.to_date, phone_number: "555-0100")

    result = update(:admin, :ward, first_name: "Changed")

    assert_equal "Changed", person(:ward).reload.first_name
    assert_not result.value.key?("phone_number")
  end

  test "on a build with update_profile?, someone it refuses is refused by name, where the page drops the change" do
    with_policy_query(PersonPolicy, :update?, proc { true }) do
      with_policy_query(PersonPolicy, :update_profile?, proc { user.admin? }) do
        assert_unchanged(/\ANot allowed: first_name and bio\z/, :alpha_member) { update(:alpha_member, :alpha_member, first_name: "Changed", bio: "x") }
        assert_not update(:admin, :alpha_member, bio: "Admin").error?
      end
    end
  end

  if Person.method_defined?(:assign_field_values)
    test "a blank required field blocks it as on the page, without naming the field" do
      person(:ward).update!(birthday: 30.years.ago.to_date)
      PersonField.create!(name: "Required Thing", key: "required_thing", data_type: :string, required: true,
        read_permission: "everyone", write_permission: "self_and_leaders")
      with_feature(:person_fields) do
        sign_in user(:admin)
        patch person_path(person(:ward)), params: { person: { first_name: "Page" } }
        assert_response :unprocessable_entity
        sign_out user(:admin)

        assert_unchanged(/\AA required profile field is blank/, :ward) { update(:admin, :ward, first_name: "Changed") }
        assert_equal "A required profile field is blank; complete it on their profile page",
          call_tool("create_person", user: user(:admin), first_name: "New", last_name: "Comer").error
        assert_not Person.exists?(first_name: "New")
      end
    end

    test "a minor's withheld built-ins aren't writable here even by someone with the field's write level" do
      person(:ward).update!(birthday: 10.years.ago.to_date, phone_number: "555-0100")
      PersonField.ensure_system_fields!
      assert_includes person(:ward).writable_fields_for(person(:admin)).map(&:system_source), "phone_number"

      with_feature(:person_fields) do
        assert_unchanged(/phone_number/, :ward) { update(:admin, :ward, phone_number: "555-0199") }
        assert_unchanged(/\ANot allowed: email/, :ward) { update(:admin, :ward, email: "changed@example.com") }
        assert_equal "555-0100", person(:ward).reload.phone_number
      end
    end
  end

  test "a read token and the setting being off refuse it" do
    assert_unchanged("Not allowed", :ward) { update(:admin, :ward, bio: "x", scopes: "mcp_read") }
    assert_unchanged("Writes disabled", :ward) { update(:admin, :ward, bio: "x", writes_enabled: false) }
  end

  test "hooks run, and the audit row names the token's user" do
    assert_hook_runs("people - update") { update(:alpha_manager, :ward, bio: "Hooked") }
    assert_equal user(:alpha_manager).id, AuditLog.where(item_type: "Person", item_id: person(:ward).id, event: "update").order(:created_at).last.whodunnit
  end

  test "a save that changes nothing fires the hook, as on the page, and logs no change" do
    Hook.create!(name: "MCP test hook", event: "people - update", code: "Thread.current[:mcp_hook_model] = model")
    Thread.current[:mcp_hook_model] = nil
    result = with_settings(mcp_write_enabled: "true") do
      Mcp::Tools::UpdatePerson.run(mcp_context(user(:admin), scopes: "mcp_write"), person_id: person(:ward).neat_id, first_name: person(:ward).first_name)
    end

    assert_not result.error?
    assert_nil result.changed
    assert_empty result.changed_records
  ensure
    Thread.current[:mcp_hook_model] = nil
  end

  test "it allows and refuses as the page does, to the same stored values" do
    [
      [ :admin, :beta_member, true ],
      [ :alpha_manager, :alpha_member, true ],
      [ :alpha_member, :alpha_member, true ],
      [ :alpha_member, :ward, false ],
      [ :alpha_manager, :beta_member, false ],
      [ :beta_member, :alpha_member, false ]
    ].each do |viewer, target, allowed|
      attributes = { first_name: "Same", last_name: "Values", display_name: "Same Shown", bio: "Same bio" }
      keys = attributes.keys.map(&:to_s)

      original = person(target).reload.attributes.slice(*keys)
      sign_in user(viewer)
      patch person_path(person(target)), params: { person: attributes }
      sign_out user(viewer)
      page = person(target).reload.attributes.slice(*keys)
      assert_equal allowed, page != original, "page: #{viewer} changing #{target}"
      person(target).update!(original)

      update(viewer, target, **attributes)
      assert_equal page, person(target).reload.attributes.slice(*keys), "#{viewer} changing #{target}"
      person(target).update!(original)
    end
  end

  # What the page does with email: reports success and stores nothing.
  test "the page drops email, and the tool refuses it" do
    sign_in user(:admin)
    patch person_path(person(:ward)), params: { person: { email: "changed@example.com", bio: "Page" } }
    assert_redirected_to person_path(person(:ward))
    assert_equal "ward@example.com", user(:ward).reload.email
    assert_equal "Page", person(:ward).reload.bio
    sign_out user(:admin)

    assert_unchanged(/\ANot allowed: email/, :ward) { update(:admin, :ward, email: "changed@example.com", bio: "Tool") }
  end
end
