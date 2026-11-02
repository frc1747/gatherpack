require "test_helper"
require_relative "../../../support/mcp_world"

class Mcp::Tools::GetPersonTest < ActiveSupport::TestCase
  include McpWorld

  setup { build_mcp_world }

  def get(viewer, target)
    call_tool("get_person", user: user(viewer), person_id: person(target).neat_id)
  end

  # Other initializers may have registered extensions: put them back.
  setup { @saved_extensions = Mcp.person_extensions.dup }
  teardown { Mcp.person_extensions.replace(@saved_extensions) }

  # Each test starts with no filter and no field-level read rules, whatever this
  # build adds; the list and Person are put back afterwards.
  setup do
    @saved_filters = Mcp.person_filters.dup
    Mcp.person_filters.clear
    stub_field_rules(false)
  end
  teardown do
    Mcp.person_filters.replace(@saved_filters)
    Person.singleton_class.send(:remove_method, :method_defined?)
  end

  PROFILE_KEYS = Mcp::Tools::GetPerson::PROFILE_FIELD_KEYS
  WITHHELD_KEYS = %w[email phone_number address birthday].freeze
  ADULT_BIRTHDAY = Date.new(1990, 5, 6)

  # Makes Person.method_defined?(:readable_fields_for) answer as given.
  def stub_field_rules(defined)
    original = Person.method(:method_defined?)
    Person.define_singleton_method(:method_defined?) do |name, *rest|
      name.to_sym == :readable_fields_for ? defined : original.call(name, *rest)
    end
  end

  # An adult: filters and field rules are about whatever Mcp::MinorRule leaves.
  def fill_profile(target, birthday: ADULT_BIRTHDAY)
    person(target).update!(phone_number: "555-0100", address: "1 Main St", birthday: birthday,
      dietary_restrictions: "None", shirt_size: "M", gender: "Other", bio: "Hello")
  end

  def make_adult(target)
    person(target).update!(birthday: ADULT_BIRTHDAY)
  end

  def capture_log
    logged = StringIO.new
    original = Rails.logger
    Rails.logger = ActiveSupport::Logger.new(logged)
    yield
    logged.string
  ensure
    Rails.logger = original
  end

  # All the profile field keys are gone and the rest of the profile is complete.
  def assert_profile_without_fields(result)
    assert_nil result.error
    assert_empty PROFILE_KEYS & result.value.keys
    assert_equal [ "Ward World", "Hello" ], result.value.values_at("name", "bio")
    assert_equal [ @alpha.neat_id ], result.value["teams"].map { |team| team["id"] }
    assert result.value.key?("relationships")
  end

  test "an admin sees the profile, contact details, teams, badges and relationships" do
    person(:ward).update!(phone_number: "555-0100", address: "1 Main St", birthday: ADULT_BIRTHDAY, shirt_size: "M")
    value = get(:admin, :ward).value

    assert_equal person(:ward).neat_id, value["id"]
    assert_equal "Ward World", value["name"]
    assert_equal "ward@example.com", value["email"]
    assert_equal [ "555-0100", "1 Main St", "1990-05-06", "M" ], value.values_at("phone_number", "address", "birthday", "shirt_size")
    assert_equal [ { "id" => @alpha.neat_id, "name" => "Alpha", "manager" => false, "membership_id" => Membership.find_by!(person: person(:ward), team: @alpha).neat_id } ], value["teams"]
    assert_equal [], value["badges"]
    assert_equal [ { "label" => "Parent of", "person" => { "id" => person(:guardian).neat_id, "name" => "Guardian World" } } ],
      value["relationships"]
  end

  test "a team manager sees a member, and the manager flag" do
    make_adult(:alpha_member)

    assert_equal "alphamember@example.com", get(:alpha_manager, :alpha_member).value["email"]
    assert_equal [ true ], get(:alpha_manager, :alpha_manager).value["teams"].map { |team| team["manager"] }
  end

  test "a member sees a teammate and themselves" do
    assert_equal "Ward World", get(:alpha_member, :ward).value["name"]
    assert_equal "AlphaMember World", get(:alpha_member, :alpha_member).value["name"]
  end

  test "a member on another team can't find someone outside their teams" do
    assert_equal "Not found", get(:beta_member, :alpha_member).error
    assert_equal :error, get(:beta_member, :alpha_member).outcome
  end

  test "a guardian sees their own profile with the ward, but not the ward's profile" do
    assert_equal [ { "label" => "Child of", "person" => { "id" => person(:ward).neat_id, "name" => "Ward World" } } ],
      get(:guardian, :guardian).value["relationships"]
    assert_equal "Not found", get(:guardian, :ward).error
  end

  test "relationships outside the viewer's scope are left out" do
    assert_empty get(:alpha_member, :ward).value["relationships"]
  end

  test "teams the viewer can't see are left out" do
    @beta.update!(join_permission: :added_by_admin)
    Membership.create!(person: person(:alpha_member), team: @beta)

    assert_equal [ @alpha.neat_id ], get(:alpha_manager, :alpha_member).value["teams"].map { |team| team["id"] }
    assert_equal [ @alpha.neat_id, @beta.neat_id ].sort, get(:admin, :alpha_member).value["teams"].map { |team| team["id"] }.sort
  end

  test "badges are listed only for badges the viewer can see, and only with the badges feature" do
    Membership.create!(person: person(:beta_member), team: @alpha)
    BadgeAssignment.create!(badge: @access_badge, person: person(:beta_member))
    team_badge = create_world_badge("Beta Badge", team: @beta)
    BadgeAssignment.create!(badge: team_badge, person: person(:beta_member))

    assert_equal [ "Beta Badge", "MCP Access" ], get(:admin, :beta_member).value["badges"].map { |badge| badge["name"] }
    assert_equal [ "MCP Access" ], get(:alpha_manager, :beta_member).value["badges"].map { |badge| badge["name"] }
    with_feature(:badges, false) { assert_not get(:admin, :beta_member).value.key?("badges") }
  end

  test "an adult without a user has an empty email" do
    nobody = Person.create!(first_name: "No", last_name: "User", birthday: ADULT_BIRTHDAY)
    value = call_tool("get_person", user: user(:admin), person_id: nobody.neat_id).value

    assert value.key?("email")
    assert_nil value["email"]
  end

  test "a person with no display name is named by their names, then their ID" do
    solo = Person.create!(first_name: "Solo")
    nameless = Person.create!
    Membership.create!(person: solo, team: @alpha)
    Membership.create!(person: nameless, team: @alpha)

    assert_equal "Solo", call_tool("get_person", user: user(:admin), person_id: solo.neat_id).value["name"]
    assert_equal nameless.neat_id, call_tool("get_person", user: user(:admin), person_id: nameless.neat_id).value["name"]
    members = call_tool("get_team", user: user(:admin), team_id: @alpha.neat_id).value["members"]
    assert_includes members.map { |member| member["name"] }, "Solo"
    assert_includes members.map { |member| member["name"] }, nameless.neat_id
  end

  test "an extension whose value fails to serialize, or that raises a ScriptError, is dropped" do
    exploding = Object.new
    def exploding.as_json(*) = raise("no json")
    Mcp.person_extensions << ->(_subject, _viewer) { { lazy: Person.where("no_such_column = 1") } }
    Mcp.person_extensions << ->(_subject, _viewer) { { bad: exploding } }
    Mcp.person_extensions << ->(_subject, _viewer) { raise NotImplementedError, "later" }
    Mcp.person_extensions << ->(_subject, _viewer) { { blob: "\xFF".b.force_encoding("UTF-8") } }
    Mcp.person_extensions << ->(_subject, _viewer) { { extra: true } }
    result = get(:admin, :ward)

    assert_nil result.error
    assert_equal [ true, "Ward World" ], result.value.values_at("extra", "name")
    assert_not result.value.key?("lazy")
    assert_not result.value.key?("bad")
    assert_not result.value.key?("blob")
    assert_nothing_raised { result.to_response }
  end

  test "a wrong ID prefix or a malformed ID is not found" do
    assert_equal "Not found", call_tool("get_person", user: user(:admin), person_id: @alpha.neat_id).error
    assert_equal "Not found", call_tool("get_person", user: user(:admin), person_id: "nonsense").error
  end

  test "an extension's keys are added and can't replace the profile's own" do
    seen = []
    Mcp.person_extensions << ->(subject, viewer) { seen << [ subject, viewer ]; { fields: { "example_key" => "example" }, name: "Hijacked" } }
    value = get(:alpha_manager, :ward).value

    assert_equal({ "example_key" => "example" }, value["fields"])
    assert_equal "Ward World", value["name"]
    assert_equal [ [ person(:ward), person(:alpha_manager) ] ], seen
  end

  test "an extension is not called when the viewer can't see the person" do
    called = false
    Mcp.person_extensions << ->(_subject, _viewer) { called = true; {} }
    get(:beta_member, :alpha_member)

    assert_not called
  end

  test "an extension that raises or returns a non-hash is dropped and logged, and the others still apply" do
    Mcp.person_extensions << ->(_subject, _viewer) { raise "boom" }
    Mcp.person_extensions << ->(_subject, _viewer) { "not a hash" }
    Mcp.person_extensions << ->(_subject, _viewer) { { extra: true } }
    logged = StringIO.new
    original = Rails.logger
    Rails.logger = ActiveSupport::Logger.new(logged)
    result = get(:admin, :ward)
    Rails.logger = original

    assert_nil result.error
    assert_equal true, result.value["extra"]
    assert_equal "Ward World", result.value["name"]
    assert_match(/extension failed.*boom/, logged.string)
  end

  # --- Filters

  test "with no filter and no field rules, every profile field key is returned, an empty one as null" do
    fill_profile(:ward)
    value = get(:alpha_member, :ward).value

    assert_equal [ "ward@example.com", "555-0100", "1990-05-06", "1 Main St", "None", "M", "Other" ], value.values_at(*PROFILE_KEYS)

    person(:ward).update!(phone_number: nil)
    value = get(:alpha_member, :ward).value
    assert value.key?("phone_number")
    assert_nil value["phone_number"]
  end

  test "the output schema doesn't require the profile field keys" do
    assert_empty PROFILE_KEYS & Mcp::Tools::GetPerson.output_schema[:required]
    assert_empty PROFILE_KEYS - Mcp::Tools::GetPerson.output_schema[:properties].keys.map(&:to_s)
  end

  test "a filter gets the person and the viewer, and keys it doesn't keep are omitted, not null" do
    fill_profile(:ward)
    seen = []
    Mcp.person_filters << ->(subject, viewer) { seen << [ subject, viewer ]; %w[email shirt_size] }
    value = get(:alpha_manager, :ward).value

    assert_equal [ [ person(:ward), person(:alpha_manager) ] ], seen
    assert_equal %w[email shirt_size], PROFILE_KEYS & value.keys
    assert_equal [ "ward@example.com", "M" ], value.values_at("email", "shirt_size")
    assert_equal [ "Ward World", "Hello" ], value.values_at("name", "bio")
  end

  test "a filter may name keys as symbols, and only profile field keys are affected" do
    Mcp.person_filters << ->(_subject, _viewer) { [ :gender, :not_a_key ] }
    value = get(:admin, :ward).value

    assert_equal %w[gender], PROFILE_KEYS & value.keys
    assert_not value.key?("not_a_key")
    assert_equal "Ward World", value["name"]
  end

  test "a filter that keeps nothing omits the keys without logging a failure" do
    fill_profile(:ward)
    Mcp.person_filters << ->(_subject, _viewer) { [] }
    result = nil
    logged = capture_log { result = get(:alpha_member, :ward) }

    assert_profile_without_fields(result)
    assert_no_match(/filter failed/, logged)
  end

  test "with two filters a key must be kept by both" do
    make_adult(:ward)
    Mcp.person_filters << ->(_subject, _viewer) { %w[email phone_number gender] }
    Mcp.person_filters << ->(_subject, _viewer) { %w[phone_number gender address] }

    assert_equal %w[phone_number gender], PROFILE_KEYS & get(:admin, :ward).value.keys
  end

  test "a filter is not called when the viewer can't see the person" do
    called = false
    Mcp.person_filters << ->(_subject, _viewer) { called = true; [] }
    get(:beta_member, :alpha_member)

    assert_not called
  end

  test "an extension can't put back a key a filter left out" do
    fill_profile(:ward)
    Mcp.person_filters << ->(_subject, _viewer) { [] }
    Mcp.person_extensions << ->(_subject, _viewer) { { phone_number: "555-0199", extra: true } }
    result = get(:alpha_member, :ward)

    assert_profile_without_fields(result)
    assert_equal true, result.value["extra"]
  end

  test "a filter that raises omits the keys, keeps the profile and is logged" do
    fill_profile(:ward)
    Mcp.person_filters << ->(_subject, _viewer) { raise "boom" }
    result = nil
    logged = capture_log { result = get(:alpha_member, :ward) }

    assert_profile_without_fields(result)
    assert_match(/filter failed.*boom/, logged)
  end

  test "a filter that raises a ScriptError omits the keys" do
    fill_profile(:ward)
    Mcp.person_filters << ->(_subject, _viewer) { raise NotImplementedError, "later" }

    assert_profile_without_fields(get(:alpha_member, :ward))
  end

  test "a filter that returns something other than an Array omits the keys and is logged" do
    fill_profile(:ward)
    [ "email", nil, { email: true }, Person.none ].each do |returned|
      Mcp.person_filters.replace([ ->(_subject, _viewer) { returned } ])
      result = nil
      logged = capture_log { result = get(:alpha_member, :ward) }

      assert_profile_without_fields(result)
      assert_match(/filter failed.*not an Array/, logged)
    end
  end

  test "a filter whose query fails omits the keys, and the request's transaction survives" do
    fill_profile(:ward)
    Mcp.person_filters << ->(_subject, _viewer) { Person.where("no_such_column = 1").to_a }
    Mcp.person_extensions << ->(_subject, _viewer) { { people: Person.count } }
    result = nil
    logged = capture_log { result = get(:alpha_member, :ward) }

    assert_profile_without_fields(result)
    assert_equal Person.count, result.value["people"]
    assert_match(/filter failed.*StatementInvalid/, logged)
  end

  test "a filter that raises Rollback omits the keys and is logged" do
    fill_profile(:ward)
    Mcp.person_filters << ->(_subject, _viewer) { raise ActiveRecord::Rollback }
    result = nil
    logged = capture_log { result = get(:alpha_member, :ward) }

    assert_profile_without_fields(result)
    assert_match(/filter failed.*rolled back/, logged)
  end

  test "one failing filter omits the keys even when another keeps them" do
    fill_profile(:ward)
    Mcp.person_filters << ->(_subject, _viewer) { PROFILE_KEYS.dup }
    Mcp.person_filters << ->(_subject, _viewer) { raise "boom" }

    assert_profile_without_fields(get(:alpha_member, :ward))
  end

  test "field rules with no filter omit the keys for every viewer" do
    fill_profile(:ward)
    stub_field_rules(true)

    assert_profile_without_fields(get(:alpha_member, :ward))
    assert_empty PROFILE_KEYS & get(:admin, :ward).value.keys
  end

  test "field rules with a filter follow the filter" do
    make_adult(:ward)
    stub_field_rules(true)
    Mcp.person_filters << ->(_subject, _viewer) { %w[email] }

    assert_equal %w[email], PROFILE_KEYS & get(:alpha_member, :ward).value.keys
  end

  # --- Minors (Mcp::MinorRule)

  # Admin, manager, guardian and self. The guardian shares the team: being a
  # guardian alone doesn't open the profile.
  def minor_viewers
    Membership.create!(person: person(:guardian), team: @alpha)
    %i[admin alpha_manager guardian ward]
  end

  def assert_contact_details_withheld(value)
    assert_empty WITHHELD_KEYS & value.keys
    assert_equal [ "None", "M", "Other", "Hello" ], value.values_at("dietary_restrictions", "shirt_size", "gender", "bio")
    assert_equal [ @alpha.neat_id ], value["teams"].map { |team| team["id"] }
    assert value.key?("relationships")
    assert value.key?("badges")
  end

  test "every viewer gets no contact details for a 16-year-old, and the other keys remain" do
    fill_profile(:ward, birthday: 16.years.ago.to_date)

    minor_viewers.each { |viewer| assert_contact_details_withheld(get(viewer, :ward).value) }
  end

  test "every viewer gets no contact details for someone with no birthday on file" do
    fill_profile(:ward, birthday: nil)

    minor_viewers.each { |viewer| assert_contact_details_withheld(get(viewer, :ward).value) }
  end

  test "every viewer gets an adult's contact details" do
    fill_profile(:ward)

    minor_viewers.each do |viewer|
      assert_equal [ "ward@example.com", "555-0100", "1 Main St", "1990-05-06" ], get(viewer, :ward).value.values_at(*WITHHELD_KEYS), viewer
    end
  end

  test "the details are withheld the day before the 18th birthday and returned on it" do
    fill_profile(:ward, birthday: Date.new(2008, 5, 6))

    travel_to(Time.utc(2026, 5, 5, 12)) { assert_contact_details_withheld(get(:admin, :ward).value) }
    travel_to(Time.utc(2026, 5, 6, 12)) { assert_empty WITHHELD_KEYS - get(:admin, :ward).value.keys }
  end

  test "every viewer gets no contact details for a birthday in year 0010" do
    fill_profile(:ward, birthday: Date.new(10, 5, 6))

    minor_viewers.each { |viewer| assert_contact_details_withheld(get(viewer, :ward).value) }
  end

  test "the birthday check uses the app's time zone" do
    fill_profile(:ward, birthday: Date.new(2008, 3, 12))

    travel_to Time.utc(2026, 3, 11, 12) do
      with_settings(time_zone: "Pacific/Auckland") { assert_empty WITHHELD_KEYS - get(:admin, :ward).value.keys }
      with_settings(time_zone: "Etc/UTC") { assert_contact_details_withheld(get(:admin, :ward).value) }
    end
  end

  test "a filter that keeps every key doesn't bring a minor's details back" do
    fill_profile(:ward, birthday: 16.years.ago.to_date)
    Mcp.person_filters << ->(_subject, _viewer) { PROFILE_KEYS.dup }

    minor_viewers.each { |viewer| assert_contact_details_withheld(get(viewer, :ward).value) }
  end

  test "with a filter, an adult's keys follow the filter" do
    fill_profile(:ward)
    Mcp.person_filters << ->(_subject, _viewer) { %w[email gender] }

    assert_equal %w[email gender], PROFILE_KEYS & get(:admin, :ward).value.keys
  end

  test "a filter's omissions still apply to a minor's other keys" do
    fill_profile(:ward, birthday: 16.years.ago.to_date)
    Mcp.person_filters << ->(_subject, _viewer) { %w[email shirt_size] }

    assert_equal %w[shirt_size], PROFILE_KEYS & get(:admin, :ward).value.keys
  end

  test "an extension can't put back a minor's details" do
    fill_profile(:ward, birthday: 16.years.ago.to_date)
    Mcp.person_extensions << ->(_subject, _viewer) { { email: "x@example.com", phone_number: "555-0199", address: "2 Main St", birthday: "2010-01-01", extra: true } }
    value = get(:admin, :ward).value

    assert_contact_details_withheld(value)
    assert_equal true, value["extra"]
  end

  test "the rule isn't a filter: field rules with no filter still omit every key, for an adult too" do
    fill_profile(:ward)
    stub_field_rules(true)

    assert_profile_without_fields(get(:admin, :ward))
    assert_empty Mcp.person_filters
    # Only a build with field rules has a reason to register one.
    assert_empty @saved_filters unless Person.public_method_defined?(:readable_fields_for)
  end

  test "a minor's result gives no reason per person, only fewer keys" do
    fill_profile(:alpha_member)
    fill_profile(:ward, birthday: 16.years.ago.to_date)

    assert_equal get(:admin, :alpha_member).value.keys - WITHHELD_KEYS, get(:admin, :ward).value.keys
  end

  test "the description says these keys can be missing, in general terms" do
    description = Mcp::Tools::GetPerson.description

    assert_match(/Email, phone number, address and birthday are never given here for anyone under 18 or with no birthday on file/, description)
  end

  # --- First and last name (the edit form's, PersonPolicy#update?)

  test "first and last name go to the person, their manager and an admin; the name stays" do
    person(:ward).update!(display_name: "Sky")

    %i[ward alpha_manager admin].each do |viewer|
      value = get(viewer, :ward).value

      assert_equal [ "Ward", "World", "Sky" ], value.values_at("first_name", "last_name", "name"), viewer
    end
  end

  test "a teammate gets the name only, with the other two left out, not null" do
    person(:ward).update!(display_name: "Sky")
    Membership.create!(person: person(:guardian), team: @alpha)

    %i[alpha_member guardian].each do |viewer|
      value = get(viewer, :ward).value

      assert_equal "Sky", value["name"]
      assert_not value.key?("first_name"), viewer
      assert_not value.key?("last_name"), viewer
      assert_not_includes value.to_json, "Ward"
    end
  end

  test "first and last name are there exactly when the viewer may update the person" do
    %i[admin alpha_manager alpha_member guardian ward].each do |viewer|
      Membership.find_or_create_by!(person: person(viewer), team: @alpha) unless viewer == :admin
      expected = PersonPolicy.new(user(viewer), person(:ward)).update?

      assert_equal expected, get(viewer, :ward).value.key?("first_name"), viewer
      assert_equal expected, get(viewer, :ward).value.key?("last_name"), viewer
    end
  end

  test "an extension can't put back first or last name" do
    Mcp.person_extensions << ->(_subject, _viewer) { { first_name: "Leaked", last_name: "Leaked", extra: true } }
    value = get(:alpha_member, :ward).value

    assert_not value.key?("first_name")
    assert_not value.key?("last_name")
    assert_equal true, value["extra"]
  end

  test "the output schema doesn't require first or last name, and the description says who gets them" do
    assert_empty %w[first_name last_name] & Mcp::Tools::GetPerson.output_schema[:required]
    assert_match(/First and last name are given only where you may edit the person/, Mcp::Tools::GetPerson.description)
  end

  test "membership IDs go only to viewers who may remove the membership, and not for an inherited team" do
    parent = create_world_team("Alpha Parent")
    @alpha.update!(parent: parent)
    membership = Membership.find_by!(person: person(:ward), team: @alpha)
    id_for = ->(viewer, team) { get(viewer, :ward).value["teams"].find { |row| row["id"] == team.neat_id }["membership_id"] }

    assert_equal membership.neat_id, id_for.call(:admin, @alpha)
    assert_equal membership.neat_id, id_for.call(:alpha_manager, @alpha)
    assert_nil id_for.call(:admin, parent)
    assert_nil id_for.call(:alpha_member, @alpha)
    assert_nil id_for.call(:ward, @alpha)
  end

  test "a membership ID is there exactly when remove_team_member accepts it" do
    target = Membership.find_by!(person: person(:ward), team: @alpha)

    %i[admin alpha_manager alpha_member ward].each do |viewer|
      listed = get(viewer, :ward).value["teams"].find { |row| row["id"] == @alpha.neat_id }
      removed = changes_rows?(Membership) { call_tool("remove_team_member", user: user(viewer), membership_id: target.neat_id) }

      assert_equal removed, listed["membership_id"] == target.neat_id, viewer
    end
  end

  test "on a self-service badge, a plain member gets the ID of their own assignment only" do
    badge = create_world_badge_with(:has_account)
    own = BadgeAssignment.create!(badge: badge, person: person(:alpha_member))
    teammate = BadgeAssignment.create!(badge: badge, person: person(:ward))
    id_for = ->(viewer, holder) { get(viewer, holder).value["badges"].find { |row| row["id"] == badge.neat_id }["badge_assignment_id"] }

    assert_equal own.neat_id, id_for.call(:alpha_member, :alpha_member)
    assert_nil id_for.call(:alpha_member, :ward)
    assert_equal teammate.neat_id, id_for.call(:alpha_manager, :ward)
  end

  test "empty contact details come back as null" do
    person(:ward).update_columns(birthday: ADULT_BIRTHDAY, bio: "", phone_number: "", address: "", dietary_restrictions: "", shirt_size: "", gender: "")
    value = get(:alpha_manager, :ward).value

    %w[bio phone_number address dietary_restrictions shirt_size gender].each do |key|
      assert value.key?(key), key
      assert_nil value[key], key
    end
  end

  test "badge assignment IDs go only to viewers who may remove the assignment" do
    badge = create_world_badge_with(:added_by_manager, team: @alpha)
    assignment = BadgeAssignment.create!(badge: badge, person: person(:ward))
    id_for = ->(viewer) { get(viewer, :ward).value["badges"].find { |row| row["id"] == badge.neat_id }["badge_assignment_id"] }

    assert_equal assignment.neat_id, id_for.call(:admin)
    assert_equal assignment.neat_id, id_for.call(:alpha_manager)
    assert_nil id_for.call(:alpha_member)
    assert_nil id_for.call(:ward)
  end

  test "a badge assignment ID is there exactly when remove_badge accepts it" do
    [ @access_badge, create_world_badge_with(:added_by_manager, team: @alpha), create_world_badge_with(:has_account),
      create_world_badge_with(:added_by_manager_or_self), create_world_badge_with(:added_by_admin_or_self) ].each do |badge|
      target = BadgeAssignment.create!(badge: badge, person: person(:ward))

      %i[admin alpha_manager alpha_member ward].each do |viewer|
        listed = get(viewer, :ward).value["badges"].find { |row| row["id"] == badge.neat_id }
        removed = changes_rows?(BadgeAssignment) { call_tool("remove_badge", user: user(viewer), badge_assignment_id: target.neat_id) }

        assert_equal removed, listed&.dig("badge_assignment_id") == target.neat_id, "#{viewer} on #{badge.name}"
      end
    end
  end
end
