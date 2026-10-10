require "test_helper"

class TimeKiosk::ConfigTest < ActiveSupport::TestCase
  setup do
    @store = Settings.instance.store
    @saved = @store.transaction(true) { %i[time_kiosk_allow_unassigned time_kiosk_return_seconds time_kiosk_users_team].index_with { |key| @store[key] } }
  end

  teardown do
    @store.transaction { @saved.each { |key, value| @store[key] = value } }
  end

  test "defaults leave the kiosk as it is" do
    write(time_kiosk_allow_unassigned: "true", time_kiosk_return_seconds: "0", time_kiosk_users_team: "")
    assert TimeKiosk::Config.allow_unassigned?
    assert_equal 0, TimeKiosk::Config.return_seconds
    assert_nil TimeKiosk::Config.users_team
  end

  test "a missing value counts as allowing unassigned punches" do
    write(time_kiosk_allow_unassigned: nil)
    assert TimeKiosk::Config.allow_unassigned?
  end

  test "reads values written by another process without a restart" do
    team = teams(:one)
    write(time_kiosk_allow_unassigned: "false", time_kiosk_return_seconds: "15", time_kiosk_users_team: team.id)
    assert_not TimeKiosk::Config.allow_unassigned?
    assert_equal 15, TimeKiosk::Config.return_seconds
    assert_equal team, TimeKiosk::Config.users_team
  end

  test "a negative return time counts as off and a deleted team as blank" do
    write(time_kiosk_return_seconds: "-5", time_kiosk_users_team: SecureRandom.uuid)
    assert_equal 0, TimeKiosk::Config.return_seconds
    assert_nil TimeKiosk::Config.users_team
  end

  test "threads can read at the same time" do
    threads = 4.times.map { Thread.new { 50.times { TimeKiosk::Config.allow_unassigned? } } }
    assert_nothing_raised { threads.each(&:join) }
  end

  private

  def write(values)
    @store.transaction { values.each { |key, value| @store[key] = value } }
  end
end
