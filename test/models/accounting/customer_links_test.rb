require "test_helper"
require_relative "../../support/accounting_world"

class Accounting::CustomerLinksTest < ActiveSupport::TestCase
  include AccountingWorld

  setup do
    @gateway = create_quickbooks_gateway(connected: false, match_strategies: "reference name email")
    @admin = create_linkable_person("Andrew", "Fuller", email: "andrew.fuller@example.com", admin: true)
    @nancy = create_linkable_person("Nancy", "Davolio", email: "nancy.davolio@example.com")
    @links = Accounting::CustomerLinks.new(@gateway)
  end

  teardown { reset_fake_quickbooks }

  # -- Suggestions --

  test "name matches ignore case, punctuation and accents, and read Last, First" do
    renee = create_linkable_person("Renée", "O'Leary")
    davolio = create_customer_record(@gateway, "1", name: "DAVOLIO, Nancy.")
    oleary = create_customer_record(@gateway, "2", name: "Renee OLeary")
    nobody = create_customer_record(@gateway, "3", name: "Janet Leverling")

    found = @links.suggestions_for([ davolio, oleary, nobody ])

    assert_equal [ [ @nancy, "name", "name match" ] ], summary(found["1"])
    assert_equal [ [ renee, "name", "name match" ] ], summary(found["2"])
    assert_empty found["3"]
  end

  test "a name matches the name a person goes by too" do
    peggy = create_linkable_person("Margaret", "Peacock")
    peggy.update!(display_name: "Peggy Peacock")
    customer = create_customer_record(@gateway, "1", name: "Peacock, Peggy")

    assert_equal [ peggy ], @links.suggestions_for([ customer ])["1"].map(&:person)
  end

  test "an email match suggests the person and their wards" do
    laura = create_linkable_person("Laura", "Callahan")
    anne = create_linkable_person("Anne", "Callahan")
    parent = create_linkable_person("Robert", "Callahan", email: "robert.callahan@example.com")
    add_guardian(parent, laura, by: @admin)
    add_guardian(parent, anne, by: @admin)
    customer = create_customer_record(@gateway, "1", name: "Callahan family", email: "Robert.Callahan@example.com ")

    found = @links.suggestions_for([ customer ])["1"]

    assert_equal [
      [ parent, "email", "email match" ],
      [ anne, "email", "ward of Robert Callahan (email match)" ],
      [ laura, "email", "ward of Robert Callahan (email match)" ]
    ], summary(found)
    assert found.none?(&:exact)
  end

  test "a reference that's a person's GatherPack id or account email is suggested, exact when it names one person" do
    by_id = create_customer_record(@gateway, "1", name: "Someone", reference: @nancy.neat_id)
    by_email = create_customer_record(@gateway, "2", name: "Someone else", reference: "NANCY.davolio@example.com")
    shared = User.create!(email: "kings@example.com", password: "Password1!")
    robert = Person.create!(user: shared, first_name: "Robert", last_name: "King")
    steven = Person.create!(user: shared, first_name: "Steven", last_name: "King")
    by_shared = create_customer_record(@gateway, "3", name: "The Kings", reference: "kings@example.com")
    unknown = create_customer_record(@gateway, "4", name: "Unknown", reference: "per_notarealid")

    found = @links.suggestions_for([ by_id, by_email, by_shared, unknown ])

    assert_equal [ [ @nancy, "reference", true ] ], found["1"].map { |s| [ s.person, s.strategy, s.exact ] }
    assert_equal [ [ @nancy, "reference", true ] ], found["2"].map { |s| [ s.person, s.strategy, s.exact ] }
    assert_equal [ robert, steven ].sort_by(&:id), found["3"].map(&:person).sort_by(&:id)
    assert found["3"].none?(&:exact)
    assert_empty found["4"]
  end

  test "strategies are tried in the source's order, and only the chosen ones" do
    customer = create_customer_record(@gateway, "1", name: "Nancy Davolio", email: "nancy.davolio@example.com")

    @gateway.update!(match_strategies: "email name")
    assert_equal [ "email" ], Accounting::CustomerLinks.new(@gateway).suggestions_for([ customer ])["1"].map(&:strategy)

    @gateway.update!(match_strategies: "name")
    assert_equal [ "name" ], Accounting::CustomerLinks.new(@gateway).suggestions_for([ customer ])["1"].map(&:strategy)

    @gateway.update!(match_strategies: "")
    assert_equal %w[ name email ], @gateway.match_strategy_list
  end

  test "people already linked to the customer aren't suggested again" do
    customer = create_customer_record(@gateway, "1", name: "Nancy Davolio")
    @links.link!("1", @nancy, source: "manual", created_by: @admin)

    assert_empty @links.suggestions_for([ customer ])["1"]
  end

  # -- Automatic links --

  test "an exact reference links automatically; an ambiguous one doesn't" do
    exact = create_customer_record(@gateway, "1", name: "Someone", reference: @nancy.neat_id)
    shared = User.create!(email: "kings@example.com", password: "Password1!")
    Person.create!(user: shared, first_name: "Robert", last_name: "King")
    Person.create!(user: shared, first_name: "Steven", last_name: "King")
    ambiguous = create_customer_record(@gateway, "2", name: "The Kings", reference: "kings@example.com")

    made = @links.link_exact_references([ exact, ambiguous ])

    assert_equal [ [ "1", @nancy, "reference" ] ], made.map { |link| [ link.customer_external_id, link.person, link.source ] }
    assert_not @links.covered?("2")
  end

  test "an exact reference links automatically even when reference comes after name" do
    @gateway.update!(match_strategies: "name reference")
    customer = create_customer_record(@gateway, "1", name: "Nancy Davolio", reference: @nancy.neat_id)

    made = Accounting::CustomerLinks.new(@gateway).link_exact_references([ customer ])

    assert_equal [ [ "1", @nancy, "reference" ] ], made.map { |link| [ link.customer_external_id, link.person, link.source ] }
  end

  test "references don't link when the reference strategy is off" do
    @gateway.update!(match_strategies: "name email")
    customer = create_customer_record(@gateway, "1", name: "Someone", reference: @nancy.neat_id)

    assert_empty Accounting::CustomerLinks.new(@gateway).link_exact_references([ customer ])
  end

  test "a sync links new customers by exact reference and fires customer unlinked for the rest" do
    @gateway.update!(match_field_path: "Notes", synced_entities: "Customer")
    @gateway.record_state!(realm_id: AccountingWorld::REALM, connection_status: "connected")
    @gateway.create_accounting_credential!(access_token: "access-token", access_token_expires_at: 1.hour.from_now,
      refresh_token: "refresh-token", refresh_token_expires_at: 90.days.from_now)
    rows = qbo_json("customers").dig("QueryResponse", "Customer")
    rows[0]["Notes"] = @nancy.neat_id
    rows[1]["Active"] = true
    fake_quickbooks.on(:get, "/query", body: { "QueryResponse" => { "Customer" => rows } })
    Hook.create!(name: "Unlinked customer", event: "accounting - customer unlinked",
      code: "model.gateway.record_state!(unlinked: Array(model.gateway.configuration['unlinked']) + [ model.customer_external_id ])")
    Hook.create!(name: "Linked", event: "accounting_customer_links - create", code: "model.gateway.record_state!(linked_by_hook: model.person_id)")

    Accounting::Sync.new(@gateway).full

    link = @gateway.accounting_customer_links.sole
    assert_equal [ "58", @nancy, "reference" ], [ link.customer_external_id, link.person, link.source ]
    @gateway.reload
    assert_equal [ "59" ], @gateway.configuration["unlinked"]
    assert_equal @nancy.id, @gateway.configuration["linked_by_hook"]
  end

  test "customer unlinked doesn't fire for a sub-customer counted with its linked parent" do
    @gateway.update!(customer_rollup: "parent")
    @links = Accounting::CustomerLinks.new(@gateway)
    create_customer_record(@gateway, "58", name: "Davolio family")
    @links.link!("58", @nancy, source: "manual")
    Hook.create!(name: "Unlinked customer", event: "accounting - customer unlinked", code: "raise 'should not fire'")

    sub = create_customer_record(@gateway, "59", name: "Davolio, Nancy (camp)", parent: "58")
    assert_nothing_raised { @links.after_sync([ sub ]) }
  end

  # -- Dismissals --

  test "a dismissed suggestion stays dismissed" do
    customer = create_customer_record(@gateway, "1", name: "Nancy Davolio", reference: @nancy.neat_id)
    @links.dismiss!("1", @nancy)

    assert_empty @links.suggestions_for([ customer ])["1"]
    assert_empty @links.link_exact_references([ customer ])
    assert_empty @links.link_exact_names([ customer ])
  end

  test "unlinking remembers the pair, so the automatic link doesn't come back; linking by hand clears it" do
    customer = create_customer_record(@gateway, "1", name: "Someone", reference: @nancy.neat_id)
    link = @links.link_exact_references([ customer ]).sole

    @links.unlink!(link)

    assert_not @links.covered?("1")
    assert @gateway.accounting_customer_dismissals.exists?(customer_external_id: "1", person: @nancy)
    assert_empty @links.link_exact_references([ customer ])

    @links.link!("1", @nancy, source: "manual", created_by: @admin)
    assert_not @gateway.accounting_customer_dismissals.exists?(customer_external_id: "1", person: @nancy)
    assert @links.covered?("1")
  end

  test "link all exact name matches links customers with exactly one person of that name" do
    create_linkable_person("Robert", "King")
    create_linkable_person("Robert", "King")
    unique = create_customer_record(@gateway, "1", name: "Davolio, Nancy")
    twice = create_customer_record(@gateway, "2", name: "Robert King")

    made = @links.link_exact_names([ unique, twice ], created_by: @admin)

    assert_equal [ [ "1", @nancy, "confirmed", @admin ] ], made.map { |link| [ link.customer_external_id, link.person, link.source, link.created_by ] }
  end

  test "link all exact name matches still links when email comes before name and finds the same person" do
    @gateway.update!(match_strategies: "email name")
    customer = create_customer_record(@gateway, "1", name: "Nancy Davolio", email: "nancy.davolio@example.com")

    made = Accounting::CustomerLinks.new(@gateway).link_exact_names([ customer ], created_by: @admin)

    assert_equal [ [ "1", @nancy, "confirmed" ] ], made.map { |link| [ link.customer_external_id, link.person, link.source ] }
  end

  test "link all exact name matches skips a name two people share, even when one of them was dismissed" do
    first = create_linkable_person("Robert", "King")
    create_linkable_person("Robert", "King")
    customer = create_customer_record(@gateway, "1", name: "Robert King")
    @links.dismiss!("1", first)

    assert_empty @links.link_exact_names([ customer ])
  end

  # -- Rollup --

  test "with the parent rollup, sub-customers count for the people linked above them" do
    create_customer_record(@gateway, "10", name: "Davolio family")
    create_customer_record(@gateway, "11", name: "Davolio, Nancy (camp)", parent: "10")
    create_customer_record(@gateway, "12", name: "Davolio, Nancy (travel)", parent: "11")
    create_customer_record(@gateway, "20", name: "Someone else")
    @links.link!("10", @nancy, source: "manual")

    assert_equal [ "10" ], @links.customer_ids_for(@nancy)
    assert_empty @links.people_for("12")
    assert_nil @links.rolled_up_into("12")

    @gateway.update!(customer_rollup: "parent")
    links = Accounting::CustomerLinks.new(@gateway)

    assert_equal %w[ 10 11 12 ], links.customer_ids_for(@nancy).sort
    assert_equal [ @nancy ], links.people_for("12").to_a
    assert_equal "10", links.rolled_up_into("12")
    assert links.covered?("11")
    assert_not links.covered?("20")
  end

  test "a customer can be linked to several people and a person to several customers" do
    janet = create_linkable_person("Janet", "Leverling")
    @links.link!("1", @nancy, source: "manual")
    @links.link!("1", janet, source: "manual")
    @links.link!("2", @nancy, source: "manual")

    assert_equal [ @nancy, janet ].sort_by(&:id), @links.people_for("1").sort_by(&:id)
    assert_equal %w[ 1 2 ], @links.customer_ids_for(@nancy).sort
    assert_equal @links.link!("1", @nancy, source: "confirmed"), @gateway.accounting_customer_links.find_by(customer_external_id: "1", person: @nancy)
  end

  # -- Settings and records --

  test "the QuickBooks source checks its link settings" do
    @gateway.match_strategies = "name phone"
    @gateway.customer_rollup = "family"

    assert_not @gateway.valid?
    assert @gateway.errors[:match_strategies].any?
    assert @gateway.errors[:customer_rollup].any?
    assert_includes @gateway.fields, :match_strategies
    assert_includes @gateway.fields, :customer_rollup
  end

  test "links are audited and hookable; dismissals aren't hookable" do
    link = nil
    assert_difference -> { AuditLog.where(item_type: "AccountingCustomerLink").count } do
      link = @links.link!("1", @nancy, source: "manual", created_by: @admin)
    end

    assert link.neat_id.start_with?("acl_")
    assert_includes Hook.catalog, "accounting_customer_links - create"
    assert_includes Hook.catalog, "accounting_customer_links - destroy"
    assert_includes Hook.catalog, "accounting - customer unlinked"
    assert_not Hook.catalog.any? { |entry| entry.start_with?("accounting_customer_dismissals") }
  end

  private
    def summary(suggestions)
      suggestions.map { |suggestion| [ suggestion.person, suggestion.strategy, suggestion.reason ] }
    end
end
