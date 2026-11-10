require "test_helper"

class TimeClockHandPunchesPolicyTest < ActiveSupport::TestCase
  PERMISSIONS = %w[ added_by_user added_by_team_member added_by_manager added_by_admin ].freeze
  ACTIONS = %i[ new? create? edit? update? destroy? ].freeze

  setup do
    # Club (led by @leader)
    # └── Robotics (run by @manager): @member, @classmate
    # Drama (unrelated, run by @drama_manager): @outsider
    @club = Team.create!(name: "Club", team_type: team_types(:one))
    @robotics = Team.create!(name: "Robotics", team_type: team_types(:one), parent: @club)
    @drama = Team.create!(name: "Drama", team_type: team_types(:one))

    @admin = create_person("admin", @drama)
    @admin.user.update!(admin: true)
    @leader = create_person("leader", @club, manager: true)
    @manager = create_person("manager", @robotics, manager: true)
    @drama_manager = create_person("drama-manager", @drama, manager: true)
    @member = create_person("member", @robotics)
    @classmate = create_person("classmate", @robotics)
    @outsider = create_person("outsider", @drama)
  end

  # Settings write to the shared settings file; keep these out of it.
  setup do
    @original_store = Settings.instance.store
    @store_path = Rails.root.join("tmp", "hand-punches-#{Process.pid}-#{SecureRandom.hex(4)}.pstore").to_s
    Settings.instance.store = PStore.new(@store_path)
    Settings[:time_clock_hand_punches_managers_only] = "false"
  end

  teardown do
    Settings[:time_clock_hand_punches_managers_only] = "false"
    Settings.instance.store = @original_store
    FileUtils.rm_f(@store_path)
  end

  test "the setting is a boolean in the time clock group, off by default" do
    setting = Settings.get(:time_clock_hand_punches_managers_only)

    assert_equal :boolean, setting.setting_type
    assert_equal "false", setting.default_value
    assert_equal "Time Clock", setting.group
    assert_equal "Only admins and managers enter punches by hand", setting.name
    assert setting.description.present?
  end

  test "with the setting on, a member has no hand entry on their own punches" do
    restrict_hand_punches

    [ nil, period(nil, "added_by_user"), *period_for_each_permission ].each do |period|
      ACTIONS.each do |action|
        assert_not allowed?(action, @member, punch(@member, period)), "#{action} in #{period&.permission || "no period"}"
      end
    end
  end

  test "with the setting on, a member can't record for a teammate in a team member period" do
    restrict_hand_punches

    assert_not allowed?(:create?, @member, punch(@classmate, period(@robotics, "added_by_team_member")))
  end

  test "with the setting on, a member can't open the empty new form" do
    restrict_hand_punches

    assert_not allowed?(:new?, @member, TimeClockPunch.new)
    assert_not allowed?(:create?, @member, TimeClockPunch.new)
  end

  test "with the setting on, a member still sees only their own punches" do
    mine = TimeClockPunch.create!(person: @member, start_time: 2.days.ago, end_time: 2.days.ago + 1.hour, created_by: @member)
    TimeClockPunch.create!(person: @classmate, start_time: 2.days.ago, end_time: 2.days.ago + 1.hour, created_by: @classmate)
    restrict_hand_punches

    assert_equal [ mine ], TimeClockPunchPolicy::Scope.new(@member.user, TimeClockPunch).resolve.to_a
  end

  test "the setting is read on every check" do
    policy = TimeClockPunchPolicy.new(@member.user, punch(@member))
    assert policy.update?

    restrict_hand_punches
    assert_not policy.update?

    Settings[:time_clock_hand_punches_managers_only] = "false"
    assert policy.update?
  end

  test "the setting changes nothing for admins and managers" do
    every_period = periods
    punches = [ @member, @classmate, @outsider, @manager, @leader, @admin ].flat_map do |target|
      [ punch(target), *every_period.map { |period| punch(target, period) } ]
    end
    actors = [ @admin, @leader, @manager, @drama_manager ]
    answers = -> { actors.product(punches, ACTIONS).map { |actor, record, action| allowed?(action, actor, record) } }

    with_setting_off = answers.call
    restrict_hand_punches
    with_setting_on = answers.call

    assert_equal with_setting_off, with_setting_on
    assert_includes with_setting_on, true
    assert_includes with_setting_on, false
  end

  test "with the setting off, a member keeps the rights they have today" do
    assert_not Settings[:time_clock_hand_punches_managers_only]

    assert allowed?(:new?, @member, TimeClockPunch.new)
    [ nil, period(nil, "added_by_user"), period(@robotics, "added_by_user"), period(@robotics, "added_by_team_member") ].each do |period|
      %i[ create? edit? update? destroy? ].each do |action|
        assert allowed?(action, @member, punch(@member, period)), "#{action} in #{period&.permission || "no period"}"
      end
    end
    [ period(@robotics, "added_by_manager"), period(@robotics, "added_by_admin") ].each do |period|
      %i[ create? edit? update? destroy? ].each do |action|
        assert_not allowed?(action, @member, punch(@member, period)), "#{action} in #{period.permission}"
      end
    end
  end

  private

  def restrict_hand_punches
    Settings[:time_clock_hand_punches_managers_only] = "true"
  end

  def create_person(name, team, manager: false)
    user = User.create!(email: "#{name}@example.com", password: "Password1!")
    person = Person.create!(user: user, first_name: name.capitalize, last_name: "Test")
    Membership.create!(person: person, team: team, manager: manager)
    person
  end

  def period_for_each_permission
    PERMISSIONS.map { |permission| period(@robotics, permission) }
  end

  # Every kind of period on the member's team and on a team without them, and
  # the kinds a period without a team can be.
  def periods
    period_for_each_permission +
      PERMISSIONS.map { |permission| period(@drama, permission) } +
      %w[ added_by_user added_by_admin ].map { |permission| period(nil, permission) }
  end

  def period(team, permission)
    TimeClockPeriod.create!(name: "Season", team: team, permission: permission, start_time: 10.days.ago, end_time: 10.days.from_now)
  end

  def punch(person, period = nil)
    TimeClockPunch.new(person: person, time_clock_period: period, start_time: 2.days.ago, end_time: 2.days.ago + 3.hours)
  end

  def allowed?(action, person, record)
    TimeClockPunchPolicy.new(person.user, record).public_send(action)
  end
end
