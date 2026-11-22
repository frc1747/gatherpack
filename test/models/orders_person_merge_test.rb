require "test_helper"

class OrdersPersonMergeTest < ActiveSupport::TestCase
  PREPARE = -> { Rails.application.reloader.prepare! }

  test "registers nothing without the person merge registry" do
    skip "GatherPack::PersonMerge is loaded" if defined?(GatherPack::PersonMerge)

    assert_nothing_raised(&PREPARE)
    assert_not defined?(GatherPack::PersonMerge)
  end

  test "covers every orders column that points at a person" do
    skip "GatherPack::PersonMerge is not loaded" unless defined?(GatherPack::PersonMerge)

    assert_nothing_raised(&PREPARE)
    %i[order_requests.requested_by_id order_approvals.approver_id order_request_events.actor_id
       order_request_watchers.person_id purchases.buyer_id purchases.reimburse_to_id
       order_deliveries.received_by_id order_notice_preferences.person_id order_summary_sends.person_id].each do |name|
      table, column = name.to_s.split(".")

      assert GatherPack::PersonMerge.covers?(table, column), "#{name} is not covered"
    end
    assert GatherPack::PersonMerge.covers?(:order_lines, :item_id)
    assert GatherPack::PersonMerge.covers?(:order_lines, :item_id, owner: :user)
  end
end
