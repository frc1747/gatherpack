require "test_helper"

class TimeKiosk::ConfigTest < ActiveSupport::TestCase
  teardown do
    FileUtils.rm_f(store.path)
  end

  test "an empty store leaves the kiosk as it is" do
    assert TimeKiosk::Config.allow_unassigned?
    assert_equal 0, TimeKiosk::Config.return_seconds
    assert_nil TimeKiosk::Config.users_team
  end

  test "the defaults leave the kiosk as it is" do
    write(time_kiosk_allow_unassigned: "true", time_kiosk_return_seconds: "0", time_kiosk_users_team: "")
    assert TimeKiosk::Config.allow_unassigned?
    assert_equal 0, TimeKiosk::Config.return_seconds
    assert_nil TimeKiosk::Config.users_team
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

  test "tests read their own file, not the site's settings" do
    assert_not_equal Settings.instance.store.path, store.path
  end

  test "threads can read at the same time" do
    threads = 4.times.map { Thread.new { 50.times { TimeKiosk::Config.allow_unassigned? } } }
    assert_nothing_raised { threads.each(&:join) }
  end

  private

  def store
    TimeKiosk::Config.send(:store)
  end

  def write(values)
    store.transaction { values.each { |key, value| store[key] = value } }
  end
end
