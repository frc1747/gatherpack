require "test_helper"

class RansackTest < ActiveSupport::TestCase
  setup do
    @person = Person.create!(first_name: "Zebra", last_name: "Xylophone", display_name: "Zebra Xylophone")
    @person2 = Person.create!(first_name: "Alpha", last_name: "Beta", display_name: "Alpha Beta")
    @team = Team.create!(name: "Ransack Test Team", team_type: team_types(:one))
    Membership.create!(person: @person, team: @team)
  end

  test "ransack search with _cont predicate finds matching records" do
    q = Person.ransack(first_name_or_last_name_or_display_name_cont: "Zebra")
    results = q.result(distinct: true)

    assert_includes results, @person
    assert_not_includes results, @person2
  end

  test "ransack search with _cont predicate is case sensitive by default" do
    q = Person.ransack(first_name_or_last_name_or_display_name_cont: "zebra")
    results = q.result(distinct: true)

    # _cont uses LIKE (case-sensitive) - "zebra" won't match "Zebra"
    assert_not_includes results, @person
    assert_not_includes results, @person2
  end

  test "ransack search with _i_cont predicate is case insensitive" do
    q = Person.ransack(first_name_or_last_name_or_display_name_i_cont: "zebra")
    results = q.result(distinct: true)

    assert_includes results, @person
    assert_not_includes results, @person2
  end

  test "ransack search with user association works for admins" do
    user = User.create!(email: "test@example.com", password: "password123")
    person_with_user = Person.create!(first_name: "With", last_name: "User", display_name: "With User", user: user)
    person_without_user = Person.create!(first_name: "Without", last_name: "User", display_name: "Without User")
    admin = User.create!(email: "admin@example.com", password: "password123", admin: true)

    q = Person.ransack({ user_email_cont: "test" }, auth_object: admin)
    results = q.result(distinct: true)

    assert_includes results, person_with_user
    assert_not_includes results, person_without_user
  end

  test "ransack sort links work" do
    # Only test with our created records by filtering
    q = Person.where(id: [ @person.id, @person2.id ]).ransack({ s: "last_name asc" })
    results = q.result(distinct: true).to_a

    # Alpha Beta should come before Zebra Xylophone alphabetically by last_name
    assert_equal @person2.id, results.first.id
    assert_equal @person.id, results.second.id
  end

  test "ransack search with multiple conditions" do
    q = Person.ransack(first_name_cont: "Zebra", last_name_cont: "Xylophone")
    results = q.result(distinct: true)

    assert_includes results, @person
    assert_not_includes results, @person2
  end

  test "ransack _start predicate works" do
    q = Person.ransack(first_name_start: "Z")
    results = q.result(distinct: true)

    assert_includes results, @person
    assert_not_includes results, @person2
  end

  test "ransack _end predicate works" do
    q = Person.ransack(last_name_end: "phone")
    results = q.result(distinct: true)

    assert_includes results, @person
    assert_not_includes results, @person2
  end

  test "ransack _eq predicate works" do
    q = Person.ransack(display_name_eq: "Zebra Xylophone")
    results = q.result(distinct: true)

    assert_includes results, @person
    assert_not_includes results, @person2
  end

  test "ransack distinct true removes duplicates when joining" do
    admin = User.create!(email: "admin@example.com", password: "password123", admin: true)
    # Create a user and associate with person to test distinct through a join
    user = User.create!(email: "duplicate-test@example.com", password: "password123")
    @person.update!(user: user)

    # Search through user association - should return person only once despite join
    q = Person.ransack({ user_email_cont: "duplicate-test" }, auth_object: admin)
    results = q.result(distinct: true)

    assert_equal 1, results.count
    assert_equal @person.id, results.first.id
  end

  test "only admins search people by private details, login or cards" do
    admin = User.create!(email: "admin@example.com", password: "password123", admin: true)
    member = User.create!(email: "member@example.com", password: "password123")
    name_only = %w[ display_name first_name id last_name updated_at ]

    assert_equal name_only, Person.ransackable_attributes.sort
    assert_equal name_only, Person.ransackable_attributes(member).sort
    assert_includes Person.ransackable_attributes(admin), "birthday"
    assert_includes Person.ransackable_attributes(admin), "phone_number"

    assert_empty Person.ransackable_associations
    assert_empty Person.ransackable_associations(member)
    assert_equal %w[ tokens user ], Person.ransackable_associations(admin).sort

    assert_empty User.ransackable_attributes
    assert_empty User.ransackable_attributes(member)
    assert_equal [ "email" ], User.ransackable_attributes(admin)
  end

  test "searches that reach people ignore their login and cards for non-admins" do
    member = User.create!(email: "member@example.com", password: "password123")
    admin = User.create!(email: "admin@example.com", password: "password123", admin: true)
    @person.update!(user: User.create!(email: "zebra@example.com", password: "password123"))
    Token.create!(tokenable: @person, value: "8675309")
    event = Event.create!(name: "Ransack Test Event", start_time: Time.current, event_type: event_types(:one), team: @team)
    checkin = Checkin.create!(event: event, person: @person)
    membership = @person.memberships.first

    [ nil, member ].each do |auth_object|
      assert_equal Person.ransack({}).result.to_sql, Person.ransack({ tokens_value_start: "9" }, auth_object: auth_object).result.to_sql
      assert_equal Person.ransack({}).result.to_sql, Person.ransack({ display_name_or_user_email_cont: "zzz" }, auth_object: auth_object).result.to_sql
      assert_equal Person.ransack({}).result.to_sql, Person.ransack({ s: "birthday desc" }, auth_object: auth_object).result.to_sql
      assert_includes Checkin.ransack({ person_tokens_value_start: "9" }, auth_object: auth_object).result, checkin
      assert_includes Checkin.ransack({ person_user_email_start: "zzz" }, auth_object: auth_object).result, checkin
      assert_includes Membership.ransack({ person_birthday_eq: "1900-01-01" }, auth_object: auth_object).result, membership
      assert_includes Token.ransack({ tokenable_of_Person_type_user_email_start: "zzz" }, auth_object: auth_object).result, @person.tokens.first
    end

    assert_not_includes Checkin.ransack({ person_tokens_value_start: "9" }, auth_object: admin).result, checkin
    assert_includes Checkin.ransack({ person_tokens_value_start: "8" }, auth_object: admin).result, checkin
    assert_not_includes Checkin.ransack({ person_user_email_start: "zzz" }, auth_object: admin).result, checkin
  end

  test "non-admins still search people by name through other models" do
    member = User.create!(email: "member@example.com", password: "password123")
    event = Event.create!(name: "Ransack Test Event", start_time: Time.current, event_type: event_types(:one), team: @team)
    checkin = Checkin.create!(event: event, person: @person)

    assert_includes Checkin.ransack({ person_display_name_i_cont: "zebra" }, auth_object: member).result, checkin
    assert_not_includes Checkin.ransack({ person_display_name_i_cont: "alpha" }, auth_object: member).result, checkin
    assert_includes Membership.ransack({ person_last_name_eq: "Xylophone" }, auth_object: member).result, @person.memberships.first
  end
end
