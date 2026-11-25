require "test_helper"
require_relative "../support/accounting_world"

class AccountingCustomersTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers
  include AccountingWorld

  setup do
    host! "localhost"
    @gateway = create_quickbooks_gateway(connected: false)
    @admin = create_accounting_user("Admin", admin: true)
    @builder = create_accounting_user("Builder", architect: true)
    @member = create_accounting_user("Member")
    @nancy = create_linkable_person("Nancy", "Davolio", email: "nancy.davolio@example.com")
    @customer = create_customer_record(@gateway, "58", name: "Davolio, Nancy", email: "nobody@example.com")
    @links = Accounting::CustomerLinks.new(@gateway)
  end

  teardown { reset_fake_quickbooks }

  test "the customers page lists customers that need a link with their suggestions, and linked ones" do
    janet = create_linkable_person("Janet", "Leverling")
    linked = create_customer_record(@gateway, "60", name: "Leverling household")
    @links.link!("60", janet, source: "manual")
    create_customer_record(@gateway, "61", name: "Old customer", active: false)
    sign_in @admin

    with_accounting { get accounting_connection_customers_path(@gateway) }

    assert_response :success
    assert_select "h2", text: "Needs a link (1)"
    assert_select "##{ActionView::RecordIdentifier.dom_id(@customer)}", text: /Nancy Davolio \(name match\)/
    assert_select "h2", text: "Linked (1)"
    assert_select "##{ActionView::RecordIdentifier.dom_id(linked)}", text: /Janet Leverling/
    assert_no_match "Old customer", response.body

    with_accounting { get accounting_connection_customers_path(@gateway, inactive: "1") }
    assert_match "Old customer", response.body
  end

  test "Link confirms a suggestion" do
    sign_in @admin

    with_accounting do
      post accounting_customer_links_path, params: { gateway_id: @gateway.to_param, customer_id: @customer.to_param, person_id: @nancy.to_param, suggested: "1" }
    end

    assert_redirected_to accounting_connection_customers_path(@gateway)
    link = @gateway.accounting_customer_links.sole
    assert_equal [ "58", @nancy, "confirmed", @admin.person ], [ link.customer_external_id, link.person, link.source, link.created_by ]
  end

  test "the customer page lists records and links the person picked" do
    janet = create_linkable_person("Janet", "Leverling")
    @gateway.accounting_records.create!(entity_type: "Invoice", external_id: "130", role: "charge", customer_external_id: "58",
      public_label: "Invoice 1042 · Dues", total_cents: 45_000, balance_cents: 15_000, external_url: "https://example.com/130", data: {})
    sign_in @admin

    with_accounting do
      get accounting_connection_customer_path(@gateway, @customer, candidate_q: "Leverling")
      assert_response :success
      assert_select "td", text: /Invoice 1042/
      assert_select "a[href='https://example.com/130']", text: "Open in QuickBooks"
      assert_select "#candidates", text: /Janet Leverling/

      post accounting_customer_links_path(gateway_id: @gateway.to_param, customer_id: @customer.to_param, back: "customer"),
        params: { customer_link: { person_id: janet.id } }
    end

    assert_redirected_to accounting_connection_customer_path(@gateway, @customer)
    link = @gateway.accounting_customer_links.sole
    assert_equal [ janet, "manual" ], [ link.person, link.source ]
  end

  test "Not this person keeps the suggestion away" do
    sign_in @admin

    with_accounting do
      post accounting_customer_dismissals_path, params: { gateway_id: @gateway.to_param, customer_id: @customer.to_param, person_id: @nancy.to_param }
      assert_redirected_to accounting_connection_customers_path(@gateway)
      get accounting_connection_customers_path(@gateway)
    end

    assert_no_match "Nancy Davolio (name match)", response.body
    assert @gateway.accounting_customer_dismissals.exists?(customer_external_id: "58", person: @nancy)
  end

  test "Unlink removes the link and remembers it" do
    link = @links.link!("58", @nancy, source: "confirmed")
    sign_in @admin

    with_accounting { delete accounting_customer_link_path(link) }

    assert_redirected_to accounting_connection_customers_path(@gateway)
    assert_not AccountingCustomerLink.exists?(link.id)
    assert @gateway.accounting_customer_dismissals.exists?(customer_external_id: "58", person: @nancy)
  end

  test "Link all exact name matches links each customer with exactly one person of its name" do
    create_customer_record(@gateway, "70", name: "Somebody Unknown")
    sign_in @admin

    with_accounting { post confirm_all_accounting_customer_links_path(gateway_id: @gateway.to_param) }

    assert_redirected_to accounting_connection_customers_path(@gateway)
    assert_equal "Linked 1 customer to the person with the same name.", flash[:notice]
    assert_equal [ [ "58", @nancy ] ], @gateway.accounting_customer_links.map { |link| [ link.customer_external_id, link.person ] }
  end

  test "only admins manage links" do
    link = @links.link!("58", @nancy, source: "confirmed")

    [ @builder, @member ].each do |user|
      sign_in user
      with_accounting do
        get accounting_connection_customers_path(@gateway)
        assert_redirected_to root_path
        get accounting_connection_customer_path(@gateway, @customer)
        assert_redirected_to root_path
        post accounting_customer_links_path, params: { gateway_id: @gateway.to_param, customer_id: @customer.to_param, person_id: @nancy.to_param }
        delete accounting_customer_link_path(link)
        post confirm_all_accounting_customer_links_path(gateway_id: @gateway.to_param)
        post accounting_customer_dismissals_path, params: { gateway_id: @gateway.to_param, customer_id: @customer.to_param, person_id: @nancy.to_param }
      end
      sign_out user
    end

    assert_equal [ link ], @gateway.accounting_customer_links.to_a
    assert_empty @gateway.accounting_customer_dismissals
  end

  test "the gateway page offers Customers to admins" do
    architect_admin = create_accounting_user("Architect", admin: true, architect: true)

    sign_in architect_admin
    get gateway_path(@gateway)
    assert_select "a[href='#{accounting_connection_customers_path(@gateway)}']", text: "Customers"
    sign_out architect_admin

    sign_in @builder
    get gateway_path(@gateway)
    assert_select "a", text: "Customers", count: 0
  end

  test "while the feature is off the customers pages and links refuse" do
    sign_in @admin

    with_accounting(false) do
      [ accounting_connection_customers_path(@gateway), accounting_connection_customer_path(@gateway, @customer) ].each do |path|
        get path
        assert_redirected_to root_path
        assert_equal "Accounting is turned off", flash[:notice]
      end
      post accounting_customer_links_path, params: { gateway_id: @gateway.to_param, customer_id: @customer.to_param, person_id: @nancy.to_param }
      assert_redirected_to root_path
    end

    assert_empty @gateway.accounting_customer_links
  end
end
