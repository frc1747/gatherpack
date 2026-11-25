require "test_helper"
require_relative "../../support/accounting_world"

class Accounting::FeatureTest < ActiveSupport::TestCase
  include AccountingWorld

  test "the feature is registered under Finance, off by default" do
    feature = GatherPack::Features.all.find { |f| f.key == :accounting }

    assert_equal "Finance", feature.nav_section
    assert_not feature.default_enabled
    with_accounting { assert Accounting.enabled? }
    with_accounting(false) { assert_not Accounting.enabled? }
  end

  test "the hook catalog offers records and sync failures" do
    assert_includes Hook.catalog, "accounting_records - create"
    assert_includes Hook.catalog, "accounting_records - update"
    assert_includes Hook.catalog, "accounting - sync failed"
    assert_not_includes Hook.catalog, "accounting_credentials - update"
  end

  test "the hook catalog offers billing runs and their finished and failed events, but no line record events" do
    assert_includes Hook.catalog, "accounting_billing_runs - create"
    assert_includes Hook.catalog, "accounting_billing_runs - finished"
    assert_includes Hook.catalog, "accounting_billing_lines - failed"
    assert_not_includes Hook.catalog, "accounting_billing_lines - create"
    assert_not AccountingBillingLine.include?(CanBeHooked)
  end

  test "QuickBooks is an accounting gateway" do
    source = Gateway::QuickbooksGateway # registers itself once loaded

    assert_includes Gateway.registry[:accounting], source
    assert_equal [ "HTTP_INTUIT_SIGNATURE" ], source.webhook_headers
  end
end
