require "test_helper"
require "support/inventory_world"

class InventoryDigestJobTest < ActiveJob::TestCase
  include InventoryWorld

  setup { @world = build_inventory_world }

  def emails
    enqueued_jobs.select { |job| job["job_class"] == "SendEmailJob" }.map { |job| job["arguments"] }
  end

  test "managers within reach hear about items running low, big count changes and units needing repair" do
    with_inventory(@world) do
      travel_to 2.days.ago do
        stock!(@world, 30)
      end
      record(@world, :used, 21, person: @world.member) # 9: running low
      kit = Item.create!(team: @world.robotics, name: "Drive kit")
      stock!(@world, 10, item: kit)
      record(@world, :counted, 4, item: kit, person: @world.member) # 10 to 4
      motor = tracked_item!(@world, units: 1, team: @world.robotics)
      motor.item_units.first.mark_for_repair!(by: @world.member, note: "Grinding")
      clear_enqueued_jobs

      InventoryDigestJob.perform_now

      by_address = emails.to_h { |_gateway, address, subject, body| [ address, [ subject, body ] ] }
      assert_equal [ @world.keeper, @world.manager ].map { |person| person.user.email }.sort, by_address.keys.sort
      keeper_subject, keeper_body = by_address[@world.keeper.user.email]
      assert_match "1 item running low, 1 count changed a lot, 1 unit to repair", keeper_subject
      assert_match "M4 screw", keeper_body
      assert_match "Grinding", keeper_body
      manager_subject, = by_address[@world.manager.user.email]
      assert_match "1 count changed a lot, 1 unit to repair", manager_subject
      assert_no_match "running low", manager_subject, "the screws are the club's"
    end
  end

  test "an item that was already low before the window isn't reported again" do
    with_inventory(@world) do
      travel_to 2.days.ago do
        stock!(@world, 5)
      end
      record(@world, :used, 1)
      clear_enqueued_jobs

      InventoryDigestJob.perform_now

      assert_empty emails
    end
  end

  test "a small count difference isn't reported, and items are left out unless notices are daily" do
    with_inventory(@world, inventory_reorder_notice: "off") do
      travel_to 2.days.ago do
        stock!(@world, 30)
      end
      record(@world, :counted, 25)
      record(@world, :used, 20)
      clear_enqueued_jobs

      InventoryDigestJob.perform_now

      assert_empty emails
    end
  end

  test "nothing is sent with the flag off" do
    with_inventory(@world, feature_inventory: "false") do
      stock!(@world, 1)
      record(@world, :counted, 10)
      clear_enqueued_jobs

      InventoryDigestJob.perform_now

      assert_empty emails
    end
  end

  test "Running Low Notices offers the Weekly Infodump" do
    assert_includes Inventory::Config::REORDER_NOTICE_CHOICES, [ "In the Weekly Infodump", "weekly" ]
    with_settings(inventory_reorder_notice: "weekly") { assert_equal "weekly", Inventory::Config.reorder_notice }
  end

  test "with summaries on, the job sends nothing and the summary carries the managers' section" do
    skip "needs feature/digests" unless defined?(GatherPack::Digests) && GatherPack::Digests[:inventory]

    with_inventory(@world, feature_digests: "true", inventory_reorder_notice: "weekly") do
      travel_to 10.days.ago do # before the weekly window, so the drop is new
        stock!(@world, 30)
      end
      record(@world, :used, 21, person: @world.member) # 9: running low
      clear_enqueued_jobs

      InventoryDigestJob.perform_now
      assert_empty emails, "the summaries feature sends it instead"

      entry = GatherPack::Digests[:inventory]
      assert_equal :weekly, entry.delivery
      section = entry.build.call(@world.keeper, since: 7.days.ago)
      assert_match "M4 screw", section.body
      assert_nil entry.build.call(@world.member, since: 7.days.ago), "not a manager"
    end
  end
end
