require "test_helper"
require_relative "../../support/accounting_world"

class Accounting::CustomerMatchingAccessTest < ActiveSupport::TestCase
  include AccountingWorld

  setup do
    @gateway = create_quickbooks_gateway(connected: false)
    @admin = create_accounting_user("Admin", admin: true)
    @holder = create_accounting_user("Holder")
    @other = create_accounting_user("Other")
    @badge = Badge.create!(name: "Customer Matcher", short: "Mat", color: "#336699", badge_type: badge_types(:one), permission: :added_by_admin)
    BadgeAssignment.create!(badge: @badge, person: @holder.person)
    @source_policy = ->(user) { Accounting::SourcePolicy.new(user, @gateway) }
    @link_policy = ->(user) { AccountingCustomerLinkPolicy.new(user, AccountingCustomerLink) }
  end

  test "admins always, holders of the named admin-assigned badge, and nobody else" do
    with_matching("Customer Matcher") do
      assert @source_policy.(@admin).customers?
      assert @source_policy.(@holder).customers?
      assert_not @source_policy.(@other).customers?
      assert_not @source_policy.(nil).customers?
    end
  end

  test "holders may link, unlink and link all, and see the links" do
    with_matching("customer matcher") do
      policy = @link_policy.(@holder)
      assert policy.create?
      assert policy.destroy?
      assert policy.confirm_all?
      assert_not @link_policy.(@other).create?
      assert_not @link_policy.(@other).confirm_all?
      assert_equal AccountingCustomerLink.all.to_a, AccountingCustomerLinkPolicy::Scope.new(@holder, AccountingCustomerLink).resolve.to_a
      assert_empty AccountingCustomerLinkPolicy::Scope.new(@other, AccountingCustomerLink).resolve
    end
  end

  test "a holder may Sync now, and nobody else outside admins and architects" do
    with_matching("Customer Matcher") do
      assert @source_policy.(@holder).sync?
      assert @source_policy.(@admin).sync?
      assert_not @source_policy.(@other).sync?
    end
  end

  test "a holder gets nothing else on a source" do
    with_matching("Customer Matcher") do
      policy = @source_policy.(@holder)
      assert_not policy.connect?
      assert_not policy.disconnect?
      assert_not policy.full_sync?
      assert_not policy.records?
      assert_not policy.upload?
    end
  end

  test "a badge anyone can add gives nothing, nor does a blank setting or Badges being off" do
    @badge.update_columns(permission: Badge.permissions[:added_by_current_member])
    with_matching("Customer Matcher") { assert_not @source_policy.(@holder).customers? }

    @badge.update_columns(permission: Badge.permissions[:added_by_admin])
    with_matching("") { assert_not @source_policy.(@holder).customers? }
    with_matching("Customer Matcher", badges: false) { assert_not @source_policy.(@holder).customers? }
    with_matching("No Such Badge") { assert_not @source_policy.(@holder).customers? }
    with_matching("") { assert @source_policy.(@admin).customers? }
  end

  private
    def with_matching(name, badges: true, &block)
      with_settings(feature_badges: badges.to_s, accounting_customer_matching_badge: name, &block)
    end
end
