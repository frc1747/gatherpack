require "test_helper"
require_relative "../support/accounting_world"

# Customer matching badge: its holders match customers to people (link,
# unlink, "Not this person", link all exact name matches) and nothing else.
class AccountingCustomerMatchingTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers
  include AccountingWorld

  setup do
    host! "localhost"
    @gateway = create_quickbooks_gateway(connected: false)
    @admin = create_accounting_user("Admin", admin: true)
    @holder = create_accounting_user("Holder")
    @other = create_accounting_user("Other")
    @badge = Badge.create!(name: "Customer Matcher", short: "Mat", color: "#336699", badge_type: badge_types(:one), permission: :added_by_admin)
    BadgeAssignment.create!(badge: @badge, person: @holder.person)
    @nancy = create_linkable_person("Nancy", "Davolio", email: "nancy.davolio@example.com")
    @customer = create_customer_record(@gateway, "58", name: "Davolio, Nancy", email: "nobody@example.com", reference: "ref-58")
    @gateway.accounting_records.create!(entity_type: "Invoice", external_id: "130", role: "charge", customer_external_id: "58",
      public_label: "Invoice 1042 · Dues", description: "Private memo", total_cents: 45_000, balance_cents: 15_000,
      external_url: "https://example.com/130", data: {})
    @links = Accounting::CustomerLinks.new(@gateway)
  end

  teardown { reset_fake_quickbooks }

  test "a holder opens the customers page, a customer and its candidates" do
    sign_in @holder

    with_matching do
      get accounting_connection_customers_path(@gateway)
      assert_response :success
      assert_match "Nancy Davolio", response.body

      get accounting_connection_customer_path(@gateway, @customer, candidate_q: "Davolio")
      assert_response :success
      assert_match "Invoice 1042", response.body
      get candidates_accounting_connection_customer_path(@gateway, @customer)
      assert_response :success
    end
  end

  test "a holder's customer page keeps memos and links into the books out" do
    @gateway.accounting_records.where(role: "customer").update_all(external_url: "https://example.com/c58")
    sign_in @holder

    with_matching { get accounting_connection_customer_path(@gateway, @customer) }

    assert_no_match "Private memo", response.body
    assert_select "a", text: /Open in/, count: 0
    assert_select "a[href*='/records/']", count: 0
    assert_match "Invoice 1042", response.body
  end

  test "a holder links, dismisses, unlinks and links all exact name matches" do
    sign_in @holder

    with_matching do
      post accounting_customer_links_path, params: { gateway_id: @gateway.to_param, customer_id: @customer.to_param, person_id: @nancy.to_param, suggested: "1" }
      link = @gateway.accounting_customer_links.sole
      assert_equal [ @nancy, @holder.person ], [ link.person, link.created_by ]

      delete accounting_customer_link_path(link)
      assert_empty @gateway.accounting_customer_links

      post accounting_customer_dismissals_path, params: { gateway_id: @gateway.to_param, customer_id: @customer.to_param, person_id: @nancy.to_param }
      assert_equal 1, @gateway.accounting_customer_dismissals.count

      create_customer_record(@gateway, "59", name: "Janet Leverling")
      janet = create_linkable_person("Janet", "Leverling")
      post confirm_all_accounting_customer_links_path(gateway_id: @gateway.to_param)
      assert_equal [ [ "59", janet ] ], @gateway.accounting_customer_links.map { |l| [ l.customer_external_id, l.person ] }
    end
  end

  test "a holder reaches Customers from Account Status, which shows no rules, Records or sync state" do
    sign_in @holder

    with_matching { get accounting_rules_path }

    assert_response :success
    assert_select "a[href='#{accounting_connection_customers_path(@gateway)}']", text: "Customers"
    assert_select "a", text: "Records", count: 0
    assert_select "a", text: "New rule", count: 0
  end

  test "a holder is refused everything else" do
    sign_in @holder

    with_matching do
      get accounting_connection_records_path(@gateway)
      assert_redirected_to root_path
      post sync_accounting_connection_path(@gateway)
      assert_redirected_to root_path
      post full_sync_accounting_connection_path(@gateway)
      assert_redirected_to root_path
      get connect_accounting_connection_path(@gateway)
      assert_redirected_to root_path
      post disconnect_accounting_connection_path(@gateway)
      assert_redirected_to root_path
      get new_accounting_rule_path
      assert_redirected_to root_path
      get new_accounting_billing_run_path
      assert_redirected_to root_path
      get gateway_path(@gateway)
      assert_redirected_to root_path
    end
  end

  test "someone without the badge, and a holder of an unnamed badge, are refused" do
    other_badge = Badge.create!(name: "Other Badge", short: "Mat", color: "#336699", badge_type: badge_types(:one), permission: :added_by_admin)
    BadgeAssignment.create!(badge: other_badge, person: @other.person)
    sign_in @other

    with_matching do
      get accounting_connection_customers_path(@gateway)
      assert_redirected_to root_path
      post accounting_customer_links_path, params: { gateway_id: @gateway.to_param, customer_id: @customer.to_param, person_id: @nancy.to_param }
    end

    assert_empty @gateway.accounting_customer_links
  end

  test "a badge that members can assign gives nothing" do
    @badge.update_columns(permission: Badge.permissions[:added_by_admin_or_self])
    sign_in @holder

    with_matching do
      get accounting_connection_customers_path(@gateway)
      assert_redirected_to root_path
    end
  end

  test "with no badge named, or Badges off, only admins match customers" do
    sign_in @holder

    with_settings(feature_accounting: "true", feature_badges: "true", accounting_customer_matching_badge: "") do
      get accounting_connection_customers_path(@gateway)
      assert_redirected_to root_path
    end
    with_settings(feature_accounting: "true", feature_badges: "false", accounting_customer_matching_badge: "Customer Matcher") do
      get accounting_connection_customers_path(@gateway)
      assert_redirected_to root_path
    end
  end

  test "the badge doesn't work while accounting is off, and admins are unchanged" do
    sign_in @holder
    with_matching(false) do
      get accounting_connection_customers_path(@gateway)
      assert_redirected_to root_path
      assert_equal "Accounting is turned off", flash[:notice]
    end
    sign_out @holder

    sign_in @admin
    with_matching { get accounting_connection_customers_path(@gateway) }
    assert_response :success
  end

  private
    def with_matching(accounting = true, &block)
      with_settings(feature_accounting: accounting.to_s, feature_badges: "true", accounting_customer_matching_badge: "customer matcher", &block)
    end
end
