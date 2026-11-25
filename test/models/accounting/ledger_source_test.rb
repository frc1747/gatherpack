require "test_helper"
require_relative "../../support/accounting_world"
require_relative "../../support/accounting_provider_contract"
require_relative "../../support/accounting_balance_cases"

class Accounting::LedgerSourceTest < ActiveJob::TestCase
  include AccountingWorld
  include Accounting::ProviderContract
  include AccountingBalanceCases

  setup do
    @team = create_ledger_team("Member ledgers")
    @treasurer = create_linkable_person("Grace", "Treasurer", email: "grace.treasurer@example.com", admin: true)
    @nancy = create_linkable_person("Nancy", "Ward", email: "nancy.ward@example.com")
    @dues = LedgerTag.create!(name: "Dues")
    @scholarship = LedgerTag.create!(name: "Scholarship")
    # The fixtures' ledgers are on other teams.
    @source = create_ledger_source(ledger_team_ids: @team.neat_id, credit_tag_ids: @scholarship.neat_id)
  end

  def provider_source
    @source
  end

  # The balance cases on ledgers: each customer is a ledger its person
  # owns, entries are added a minute apart, and payments and credits count
  # against the oldest charge whatever charge the case names.
  def balance_source = @source
  def balance_charge(customer, id, total:, due_on: nil)
    skip "Ledger entries have no due dates." if due_on
    balance_entry(customer, id, -total, tags: [ @dues ])
  end
  def balance_pay(customer, id, cents, charge:) = balance_entry(customer, id, cents)
  def balance_credit(customer, id, cents, charge:) = balance_entry(customer, id, cents, tags: [ @scholarship ])
  def balance_unapplied(*) = skip("Ledgers count every payment against the oldest open charge, so none sits unapplied beside one.")
  def balance_void(customer, charge) = @balance_entries.fetch(charge).update!(failed: true)
  def balance_sync = sync

  def balance_person(customer)
    person = create_linkable_person("Andrew", "Fuller")
    (@balance_ledgers ||= {})[customer] = create_ledger("Andrew Fuller dues", team: @team, owners: [ person ])
    person
  end

  def balance_entry(customer, id, cents, tags: [])
    @balance_entries ||= {}
    at = Time.zone.local(2026, 9, 1) + @balance_entries.size.minutes
    @balance_entries[id] = add_entry(@balance_ledgers.fetch(customer), cents, by: @treasurer, at: at, tags: tags)
  end

  def provider_cases
    ledger_id = SecureRandom.uuid
    entry = ->(role, amount, extra = {}) do
      { "id" => SecureRandom.uuid, "ledger_id" => ledger_id, "parent_id" => nil, "amount_cents" => amount, "remark" => "Paid by check 4471",
        "created_at" => "2026-09-01T16:00:00.000000Z", "tag_ids" => [ @dues.id ], "first_tag_name" => "Dues", "role" => role,
        "url" => "/ledgers/#{ledger_id}/ledger_entries/1", "pay_url" => "/ledger_payments/new?ledger_id=#{ledger_id}" }.merge(extra)
    end

    [
      [ "Ledger", { "id" => ledger_id, "name" => "Nancy Ward dues", "team_id" => @team.id, "person_owner_ids" => [ @nancy.id ], "url" => "/ledgers/1" },
        { customer_external_id: ledger_id, name: "Nancy Ward dues", active: true } ],
      [ "LedgerTag", { "id" => @dues.id, "name" => "Dues", "url" => "/ledger_tags/1" }, { name: "Dues" } ],
      [ "LedgerEntry", entry.call("charge", -45_000, "balance_cents" => 15_000),
        { total_cents: 45_000, balance_cents: 15_000, due_on: nil, txn_date: Date.new(2026, 9, 1), customer_external_id: ledger_id,
          item_ids: [ @dues.id ], public_label: "Charge · Dues", description: "Paid by check 4471" } ],
      [ "LedgerEntry", entry.call("payment", 30_000, "applied_to" => [ { "external_id" => "a", "amount_cents" => 30_000 } ], "unapplied_cents" => 0),
        { total_cents: 30_000, unapplied_cents: 0, public_label: "Payment", pay_url: nil } ],
      [ "LedgerEntry", entry.call("credit", 5000, "applied_to" => [], "unapplied_cents" => 5000),
        { total_cents: 5000, unapplied_cents: 5000, balance_cents: 5000, public_label: "Credit" } ]
    ]
  end

  test "is an accounting source with no due dates" do
    Gateway::StripeGateway.delete_all
    assert_includes Gateway.registry[:accounting], Gateway::LedgerSource
    assert_not_includes @source.capabilities, :due_dates
    assert_includes @source.capabilities, :deep_links
    assert_not_includes @source.capabilities, :pay_links

    Gateway::StripeGateway.create!(name: "Card payments")
    assert_includes @source.capabilities, :pay_links
  end

  test "each ledger is a customer, and its person owners are linked" do
    ledger = create_ledger("Nancy Ward dues", team: @team, owners: [ @nancy ])
    create_ledger("Club account", team: @team)

    sync
    customers = @source.accounting_records.current.where(role: "customer")

    assert_equal [ "Club account", "Nancy Ward dues" ], customers.order(:name).pluck(:name)
    assert_equal [ [ ledger.id, @nancy.id, "ledger_owner" ] ], @source.accounting_customer_links.pluck(:customer_external_id, :person_id, :source)
  end

  test "a guardian who co-owns a ward's ledger isn't linked" do
    ward = create_linkable_person("Ben", "Ward")
    add_guardian(@nancy, ward, by: @treasurer)
    ledger = create_ledger("Ben Ward dues", team: @team, owners: [ @nancy, ward ])

    sync

    assert_equal [ ward.id ], @source.accounting_customer_links.where(customer_external_id: ledger.id).pluck(:person_id)
  end

  test "395#5: a guardianship added, removed, or its type no longer a guardianship relinks the ward's ledger" do
    ward = create_linkable_person("Ben", "Ward")
    ledger = create_ledger("Ben Ward dues", team: @team, owners: [ @nancy, ward ])
    sync
    linked = -> { @source.accounting_customer_links.where(customer_external_id: ledger.id).pluck(:person_id).sort }
    both = [ @nancy.id, ward.id ].sort
    assert_equal both, linked.call

    relink = ->(&change) { with_accounting { change.call.tap { perform_enqueued_jobs only: Accounting::OwnerLinksJob } } }
    relationship = relink.call { add_guardian(@nancy, ward, by: @treasurer) }
    assert_equal [ ward.id ], linked.call

    relink.call { relationship.destroy! }
    assert_equal both, linked.call

    relationship = relink.call { add_guardian(@nancy, ward, by: @treasurer) }
    assert_equal [ ward.id ], linked.call

    relink.call { relationship.relationship_type.update!(guardianship: :none) }
    assert_equal both, linked.call
  end

  test "395#8: a ledger's own sync moves the last sync time on and clears an earlier error" do
    ledger = create_ledger("Nancy Ward dues", team: @team, owners: [ @nancy ])
    @source.sync_failed!("Timed out")
    assert_nil @source.reload.last_change_check_time

    with_accounting do
      add_entry(ledger, -45_000, by: @treasurer, tags: [ @dues ])
      perform_enqueued_jobs only: Accounting::LedgerSyncJob
    end

    @source.reload
    assert @source.last_change_check_time
    assert_nil @source.configuration["last_error"]
  end

  test "removing an ownership removes its link, and a link an admin removed stays removed" do
    ben = create_linkable_person("Ben", "Ward")
    ledger = create_ledger("Ward family", team: @team, owners: [ @nancy, ben ])
    sync

    with_accounting do
      ledger.ledger_ownerships.find_by(owner: ben).destroy!
      perform_enqueued_jobs only: Accounting::LedgerSyncJob
    end
    assert_equal [ @nancy.id ], @source.accounting_customer_links.pluck(:person_id)

    links = Accounting::CustomerLinks.new(@source)
    links.unlink!(@source.accounting_customer_links.sole)
    with_accounting do
      ledger.update!(name: "Ward family dues")
      perform_enqueued_jobs only: Accounting::LedgerSyncJob
    end

    assert_equal 0, @source.accounting_customer_links.count
    assert_equal "Ward family dues", @source.accounting_records.find_by(entity_type: "Ledger").name
  end

  test "charges are entries below zero by default, above zero with a positive charge sign" do
    ledger = create_ledger("Nancy Ward dues", team: @team, owners: [ @nancy ])
    add_entry(ledger, -10_000, by: @treasurer, at: 2.days.ago, tags: [ @dues ])
    add_entry(ledger, 4000, by: @treasurer, at: 1.day.ago)

    sync
    assert_equal({ "charge" => 10_000, "payment" => 4000 }, totals_by_role)

    @source.update!(charge_sign: "positive")
    sync
    assert_equal({ "charge" => 4000, "payment" => 10_000 }, totals_by_role)
  end

  test "payment-side entries with a credit tag are credits, and a credit never names its tag" do
    ledger = create_ledger("Nancy Ward dues", team: @team, owners: [ @nancy ])
    add_entry(ledger, -10_000, by: @treasurer, at: 2.days.ago, tags: [ @dues ])
    add_entry(ledger, 2500, by: @treasurer, at: 1.day.ago, tags: [ @scholarship ], remark: "Hardship scholarship")

    sync
    credit = @source.accounting_records.find_by(role: "credit")

    assert_equal 2500, credit.total_cents
    assert_equal "Credit", credit.public_label
    assert_equal "Hardship scholarship", credit.description
    assert_equal 7500, @source.accounting_records.find_by(role: "charge").balance_cents
  end

  test "split parents are skipped and their children counted; failed and unfinalized entries are skipped" do
    ledger = create_ledger("Nancy Ward dues", team: @team, owners: [ @nancy ])
    parent = add_entry(ledger, -12_000, by: @treasurer, at: 3.days.ago)
    dues = add_entry(ledger, -10_000, by: @treasurer, at: 3.days.ago, parent_id: parent.id, tags: [ @dues ])
    fee = add_entry(ledger, -2000, by: @treasurer, at: 3.days.ago, parent_id: parent.id)
    add_entry(ledger, 5000, by: @treasurer, at: 2.days.ago, failed: true)
    add_entry(ledger, 5000, by: @treasurer, at: 1.day.ago, finalized: false)

    sync
    entries = @source.accounting_records.current.where(entity_type: "LedgerEntry")

    assert_equal [ dues.id, fee.id ].sort, entries.pluck(:external_id).sort
    assert_equal "Charge · Dues", entries.find_by(external_id: dues.id).public_label
  end

  test "a split only part divided keeps the rest on the parent, so the ledger's balance still matches" do
    ledger = create_ledger("Nancy Ward dues", team: @team, owners: [ @nancy ])
    charge = add_entry(ledger, -30_000, by: @treasurer, at: 3.days.ago, tags: [ @dues ])
    add_entry(ledger, 0, by: @treasurer, at: 3.days.ago, parent_id: charge.id)
    add_entry(ledger, 0, by: @treasurer, at: 3.days.ago, parent_id: charge.id)

    sync
    record = @source.accounting_records.current.find_by!(external_id: charge.id)
    assert_equal [ "charge", 30_000, "Charge · Dues" ], [ record.role, record.total_cents, record.public_label ]

    part = add_entry(ledger, -10_000, by: @treasurer, at: 3.days.ago, parent_id: charge.id)
    sync
    entries = @source.accounting_records.current.where(entity_type: "LedgerEntry")

    assert_equal({ charge.id => 20_000, part.id => 10_000 }, entries.pluck(:external_id, :total_cents).to_h)
    assert_equal(-ledger.reload.balance_cents, entries.where(role: "charge").sum(:balance_cents))
  end

  test "payments count against the oldest charges first, and what's left is unapplied" do
    ledger = create_ledger("Nancy Ward dues", team: @team, owners: [ @nancy ])
    deposit = add_entry(ledger, -15_000, by: @treasurer, at: 5.days.ago, tags: [ @dues ])
    rest = add_entry(ledger, -30_000, by: @treasurer, at: 4.days.ago, tags: [ @dues ])
    first = add_entry(ledger, 20_000, by: @treasurer, at: 3.days.ago)
    second = add_entry(ledger, 40_000, by: @treasurer, at: 2.days.ago)

    sync
    record = ->(entry) { @source.accounting_records.find_by(external_id: entry.id) }

    assert_equal 0, record.call(deposit).balance_cents
    assert_equal 0, record.call(rest).balance_cents
    assert_equal [ { "external_id" => deposit.id, "amount_cents" => 15_000 }, { "external_id" => rest.id, "amount_cents" => 5000 } ], record.call(first).applied_to
    assert_equal 0, record.call(first).unapplied_cents
    assert_equal [ { "external_id" => rest.id, "amount_cents" => 25_000 } ], record.call(second).applied_to
    assert_equal 15_000, record.call(second).unapplied_cents
  end

  test "the balances agree with the ledger's own balance, sign adjusted" do
    ledger = create_ledger("Nancy Ward dues", team: @team, owners: [ @nancy ])
    add_entry(ledger, -45_000, by: @treasurer, at: 5.days.ago, tags: [ @dues ])
    add_entry(ledger, 20_000, by: @treasurer, at: 4.days.ago)
    split = add_entry(ledger, 10_000, by: @treasurer, at: 3.days.ago)
    add_entry(ledger, 6000, by: @treasurer, at: 3.days.ago, parent_id: split.id)
    add_entry(ledger, 4000, by: @treasurer, at: 3.days.ago, parent_id: split.id, tags: [ @scholarship ])
    add_entry(ledger, 9000, by: @treasurer, at: 2.days.ago, failed: true)
    add_entry(ledger, -5000, by: @treasurer, at: 1.day.ago)

    sync
    records = @source.accounting_records.current.where(entity_type: "LedgerEntry")
    owed = records.where(role: "charge").sum(:balance_cents) - records.where(role: %w[ payment credit ]).sum(:unapplied_cents)

    assert_equal(-ledger.reload.balance_cents, owed)
    assert_equal 20_000, owed
  end

  test "ledgers outside the chosen teams are ignored" do
    other = create_ledger_team("Club accounts")
    create_ledger("Nancy Ward dues", team: @team, owners: [ @nancy ])
    outside = create_ledger("Snack bar", team: other)
    add_entry(outside, -500, by: @treasurer)
    sync

    assert_equal [ "Nancy Ward dues" ], @source.accounting_records.where(role: "customer").pluck(:name)
    assert_not @source.accounting_records.exists?(customer_external_id: outside.id)
  end

  test "with no teams chosen, every team's ledgers count" do
    @source.update!(ledger_team_ids: "")
    other = create_ledger("Snack bar", team: create_ledger_team("Club accounts"))
    sync

    assert @source.accounting_records.current.exists?(role: "customer", customer_external_id: other.id)
  end

  test "settings name known teams and tags" do
    source = Gateway::LedgerSource.new(name: "Books", ledger_team_ids: "#{@team.neat_id} tm_nothing", charge_sign: "sideways")

    assert_not source.valid?
    assert source.errors[:ledger_team_ids].any?
    assert source.errors[:charge_sign].any?
  end

  test "an entry, tagging or ownership change queues a ledger sync for a covered ledger" do
    ledger = create_ledger("Nancy Ward dues", team: @team)

    with_accounting do
      assert_enqueued_with(job: Accounting::LedgerSyncJob, args: [ @source, ledger.id ]) { add_entry(ledger, -100, by: @treasurer) }
      entry = ledger.ledger_entries.first
      assert_enqueued_with(job: Accounting::LedgerSyncJob, args: [ @source, ledger.id ]) { entry.ledger_taggings.create!(ledger_tag: @dues) }
      assert_enqueued_with(job: Accounting::LedgerSyncJob, args: [ @source, ledger.id ]) { ledger.ledger_ownerships.create!(owner: @nancy) }
    end
  end

  test "a ledger sync runs one at a time with the source's other syncs" do
    ledger = create_ledger("Nancy Ward dues", team: @team)

    assert_operator Accounting::LedgerSyncJob, :<, Accounting::SyncJob
    assert_equal Accounting::FullSyncJob.new(@source).concurrency_key, Accounting::LedgerSyncJob.new(@source, ledger.id).concurrency_key
  end

  test "nothing is queued for a ledger outside the chosen teams, or while the feature is off" do
    outside = create_ledger("Snack bar", team: create_ledger_team("Club accounts"))
    covered = create_ledger("Nancy Ward dues", team: @team)

    with_accounting { assert_no_enqueued_jobs(only: Accounting::LedgerSyncJob) { add_entry(outside, -100, by: @treasurer) } }
    with_accounting(false) { assert_no_enqueued_jobs(only: Accounting::LedgerSyncJob) { add_entry(covered, -100, by: @treasurer) } }
  end

  test "a ledger sync picks up a new payment, and a removed ledger's records and links go" do
    ledger = create_ledger("Nancy Ward dues", team: @team, owners: [ @nancy ])
    charge = add_entry(ledger, -10_000, by: @treasurer, at: 1.day.ago)
    sync

    with_accounting do
      add_entry(ledger, 10_000, by: @treasurer)
      perform_enqueued_jobs only: Accounting::LedgerSyncJob
    end
    assert_equal 0, @source.accounting_records.find_by(external_id: charge.id).balance_cents

    with_accounting do
      ledger.destroy!
      perform_enqueued_jobs only: Accounting::LedgerSyncJob
    end
    assert_empty @source.accounting_records.current.where.not(role: "item")
    assert_equal 0, @source.accounting_customer_links.count
  end

  test "reading an unchanged ledger again saves nothing" do
    ledger = create_ledger("Nancy Ward dues", team: @team, owners: [ @nancy ])
    add_entry(ledger, -10_000, by: @treasurer, tags: [ @dues ])
    sync

    assert_empty Accounting::Sync.new(@source).full
    assert_empty @source.sync_ledger(ledger.id)
  end

  test "ledger customers get name suggestions like any source's" do
    ledger = create_ledger("Nancy Ward", team: @team)
    sync

    customer = @source.accounting_records.find_by(customer_external_id: ledger.id)
    suggestions = Accounting::CustomerLinks.new(@source).suggestions_for([ customer ])[ledger.id]

    assert_equal [ @nancy ], suggestions.map(&:person)
    assert_equal "name", suggestions.first.strategy
  end

  test "the nightly job reads ledger sources again every night" do
    with_accounting do
      travel_to(Date.new(2026, 11, 25).noon) do
        assert_enqueued_with(job: Accounting::FullSyncJob, args: [ @source ]) { Accounting::NightlyJob.perform_now }
      end
    end
  end

  private
    def sync
      with_accounting { Accounting::Sync.new(@source).full }
    end

    def totals_by_role
      @source.accounting_records.current.where(entity_type: "LedgerEntry").group(:role).sum(:total_cents)
    end
end
