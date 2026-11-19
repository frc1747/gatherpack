require "test_helper"
require "support/inventory_world"

class InventoryNoticesTest < ActiveJob::TestCase
  include InventoryWorld

  setup { @world = build_inventory_world }

  def emails
    enqueued_jobs.select { |job| job["job_class"] == "SendEmailJob" }.map { |job| job["arguments"] }
  end

  def addresses
    emails.map { |_gateway, address, _subject, _body| address }.sort
  end

  def addresses_of(*people)
    people.map { |person| person.user.email }.sort
  end

  # Each person's own choice, as the summaries feature's Email notices page
  # gives it (GatherPack::Digests.delivery_for), stubbed here so the test
  # runs with or without that feature merged.
  def with_choices(choices)
    added = !defined?(GatherPack::Digests)
    GatherPack.const_set(:Digests, Module.new { def self.handles?(_key) = false }) if added
    digests = GatherPack::Digests
    original = digests.method(:delivery_for) if digests.respond_to?(:delivery_for)
    digests.define_singleton_method(:delivery_for) do |_key, person|
      choices.fetch(person) { Inventory::Config.reorder_notice }.to_sym
    end
    yield
  ensure
    if added
      GatherPack.send(:remove_const, :Digests)
    elsif original
      digests.define_singleton_method(:delivery_for, original)
    else
      digests.singleton_class.remove_method(:delivery_for)
    end
  end

  # A new club item goes low: the keeper's grant reaches the club; the
  # robotics manager's own team doesn't.
  def go_low
    item = Item.create!(team: @world.club, name: "Washer #{SecureRandom.hex(2)}", home_location: @world.bin1, reorder_point: 10)
    stock!(@world, 11, item: item)
    clear_enqueued_jobs
    record(@world, :used, 1, item: item)
  end

  test "each: running low goes out right away; daily, weekly and off send nothing then" do
    { "each" => addresses_of(@world.keeper), "daily" => [], "weekly" => [], "off" => [] }.each do |notice, expected|
      with_inventory(@world, inventory_reorder_notice: notice) do
        go_low
        assert_equal expected, addresses, notice
      end
    end
  end

  test "a person's own choice beats the site's" do
    with_inventory(@world, inventory_reorder_notice: "daily") do
      with_choices(@world.keeper => "each") do
        go_low
        assert_equal addresses_of(@world.keeper), addresses
      end
    end
    with_inventory(@world, inventory_reorder_notice: "each") do
      with_choices(@world.keeper => "off") do
        go_low
        assert_empty emails
      end
    end
  end

  test "each: a count that changed a lot is emailed to the item team's managers" do
    kit = Item.create!(team: @world.robotics, name: "Drive kit")
    with_inventory(@world, inventory_reorder_notice: "each") do
      stock!(@world, 10, item: kit)
      clear_enqueued_jobs

      record(@world, :counted, 8, item: kit, person: @world.member)
      assert_empty emails, "a small difference waits for nobody"

      record(@world, :counted, 2, item: kit, person: @world.member)
      assert_equal addresses_of(@world.keeper, @world.manager), addresses
      _gateway, _address, subject, body = emails.first
      assert_match "Count changed a lot: Drive kit", subject
      assert_match "counted 2, was 8", body
      assert_match "Member Example", body
    end
  end

  test "each: a unit marked for repair is emailed; daily waits for the digest" do
    motor = tracked_item!(@world, units: 2, team: @world.robotics)
    with_inventory(@world, inventory_reorder_notice: "each") do
      clear_enqueued_jobs
      motor.item_units.find_by!(code: "MOT-1").mark_for_repair!(by: @world.member, note: "Grinding <loud>")

      assert_equal addresses_of(@world.keeper, @world.manager), addresses
      _gateway, _address, subject, body = emails.first
      assert_match "Needs repair: MOT-1", subject
      assert_match "Grinding &lt;loud&gt;", body
    end
    with_inventory(@world, inventory_reorder_notice: "daily") do
      clear_enqueued_jobs
      motor.item_units.find_by!(code: "MOT-2").mark_for_repair!(by: @world.member, note: "Smoked")
      assert_empty emails
    end
  end

  test "the digest goes only to managers who chose daily or weekly" do
    kit = Item.create!(team: @world.robotics, name: "Drive kit")
    with_inventory(@world, inventory_reorder_notice: "daily") do
      stock!(@world, 10, item: kit)
      record(@world, :counted, 2, item: kit, person: @world.member)
      clear_enqueued_jobs

      with_choices(@world.keeper => "each", @world.manager => "weekly") do
        InventoryDigestJob.perform_now
      end
      assert_equal addresses_of(@world.manager), addresses
    end
  end

  test "team managers hear nothing without a row naming them" do
    kit = Item.create!(team: @world.robotics, name: "Drive kit")
    with_inventory(@world, inventory_reorder_notice: "each", inventory_managers: "#{@world.keeper_badge.name} > #{@world.club.name}") do
      stock!(@world, 10, item: kit)
      clear_enqueued_jobs
      record(@world, :counted, 2, item: kit)

      assert_equal addresses_of(@world.keeper), addresses
      assert_not_includes InventoryNotices.managers.keys, @world.manager
    end
  end
end
