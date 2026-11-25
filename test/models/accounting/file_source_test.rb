require "test_helper"
require "csv"
require_relative "../../support/accounting_world"
require_relative "../../support/accounting_provider_contract"
require_relative "../../support/accounting_balance_cases"

class Accounting::FileSourceTest < ActiveJob::TestCase
  include AccountingWorld
  include Accounting::ProviderContract
  include AccountingBalanceCases

  setup do
    @source = create_file_source
    @treasurer = create_linkable_person("Grace", "Treasurer", email: "grace.treasurer@example.com", admin: true)
    @nancy = create_linkable_person("Nancy", "Ward", email: "nancy.ward@example.com")
  end

  def provider_source
    @source
  end

  # The balance cases on an uploaded file: each customer is a person's
  # id, each record a row, and a voided charge is a row taken out.
  def balance_source = @source
  def balance_charge(customer, id, total:, due_on: nil) = balance_row(customer, "charge", id, total, due_on: due_on)
  def balance_pay(customer, id, cents, charge:) = balance_row(customer, "payment", id, cents, applied_to: charge)
  def balance_credit(customer, id, cents, charge:) = balance_row(customer, "credit", id, cents, applied_to: charge)
  def balance_unapplied(customer, id, cents) = balance_row(customer, "payment", id, cents)
  def balance_void(customer, charge) = @balance_rows.delete(charge)

  def balance_person(customer)
    person = create_linkable_person("Andrew", "Fuller")
    (@balance_customers ||= {})[customer] = person.neat_id
    person
  end

  def balance_row(customer, role, id, cents, due_on: nil, applied_to: nil)
    amount = format("%.2f", cents / 100.0)
    applied = "#{applied_to}:#{amount}" if applied_to
    (@balance_rows ||= {})[id] = [ @balance_customers.fetch(customer), role, id, "2026-09-01", due_on&.iso8601, nil, amount, nil, applied, nil ]
  end

  def balance_sync
    return if @balance_rows.blank?

    apply(CSV.generate { |csv| csv << Accounting::Files::Template::COLUMNS; @balance_rows.each_value { |row| csv << row } })
  end

  def provider_cases
    records = read(file_fixture("accounting/dues.csv").read).records
    first = ->(type) { records.fetch(type).first }
    [
      [ "customer", first.call("customer"), { customer_external_id: "nancy ward", name: "Nancy Ward", reference: nil } ],
      [ "item", first.call("item"), { name: "Dues" } ],
      [ "charge", first.call("charge"), { number: "1042", total_cents: 45_000, balance_cents: 10_000, due_on: Date.new(2026, 10, 1),
                                          public_label: "Charge 1042 · Dues", customer_external_id: "nancy ward", item_ids: [ "dues" ] } ],
      [ "payment", first.call("payment"), { total_cents: 30_000, unapplied_cents: 0, public_label: "Payment", description: "Paid by check 4471" } ],
      [ "credit", first.call("credit"), { total_cents: 7500, unapplied_cents: 2500, balance_cents: 2500, public_label: "Credit" } ],
      [ "receipt", first.call("receipt"), { total_cents: 4000, balance_cents: 0, public_label: "Receipt R-5 · Car wash" } ],
      [ "refund", { "id" => "row-1", "customer" => "nancy ward", "number" => nil, "date" => "2026-10-02", "total_cents" => 1000,
                    "applied_to" => [], "description" => "Withdrew" }, { total_cents: 1000, public_label: "Refund" } ]
    ]
  end

  test "is an accounting source with due dates and uploads, and nothing live" do
    assert_includes Gateway.registry[:accounting], Gateway::FileSource
    assert_equal Set[:due_dates, :upload], @source.capabilities
  end

  test "the template's columns" do
    assert_equal "customer,role,number,date,due_date,item,total,balance,applied_to,description\n", Accounting::Files::Template.csv
    assert_equal Accounting::Files::Template::COLUMNS, CSV.parse_line(Accounting::Files::Template.csv)
  end

  test "rows that don't read are listed with their problems" do
    result = read(file_fixture("accounting/problems.csv").read)
    by_row = result.errors.group_by { |problem| problem["row"] }.transform_values { |problems| problems.map { |problem| problem["message"] } }

    assert_equal [ "A charge needs a number." ], by_row[2]
    assert_match "Unknown role \"donation\"", by_row[3].sole
    assert_equal 2, by_row[4].size
    assert(by_row[4].any? { |message| message.include?("\"three hundred\" isn't an amount") })
    assert_includes by_row[4], "Applied to 1099, which isn't a charge number in this file."
    assert_includes by_row[5], "No customer."
    assert(by_row[5].any? { |message| message.include?("\"yesterday\" isn't a date") })
    assert(by_row[5].any? { |message| message.include?("\"-5\" isn't an amount") })
  end

  test "a file without the needed columns, a repeated charge number and over-applied charges are refused" do
    assert_match "no role column", read("customer,total\nNancy Ward,5\n").errors.sole["message"]

    repeated = read("customer,role,number,total\nNancy Ward,charge,1,5\nNancy Ward,charge,1,6\n")
    assert_equal [ 2, 3 ], repeated.errors.map { |problem| problem["row"] }

    over = read("customer,role,number,total,applied_to\nNancy Ward,charge,1,5,\nNancy Ward,payment,,8,1:8\n")
    assert_includes over.errors.map { |problem| problem["message"] }, "More is applied to charge 1 than its total."
  end

  test "a charge's blank balance comes from what payments and credits apply to it; refunds don't lower it" do
    records = read(<<~CSV).records
      customer,role,number,total,balance,applied_to
      Nancy Ward,charge,1,100,,
      Nancy Ward,charge,2,100,60,
      Nancy Ward,payment,,150,,1;2
      Nancy Ward,refund,,20,,1
    CSV

    assert_equal [ 0, 6000 ], records["charge"].map { |charge| charge["balance_cents"] }
    payment = records["payment"].sole
    assert_equal [ { "external_id" => "1", "amount_cents" => 10_000 }, { "external_id" => "2", "amount_cents" => 5000 } ], payment["applied_to"]
    assert_equal 0, payment["unapplied_cents"]
  end

  test "a refund applied to a paid charge takes the rest of its total" do
    records = read(<<~CSV).records
      customer,role,number,total,applied_to
      Nancy Ward,charge,1042,300,
      Nancy Ward,payment,,300,1042
      Nancy Ward,refund,,50,1042
    CSV

    assert_equal [ { "external_id" => "1042", "amount_cents" => 5000 } ], records["refund"].sole["applied_to"]
    assert_equal 0, records["charge"].sole["balance_cents"]
  end

  test "applying a file copies its records, links person ids and account emails, and suggests names" do
    ward = create_linkable_person("Ben", "Ward")
    apply(file_fixture("accounting/dues.csv").read + "#{ward.neat_id},charge,1044,2026-09-01,,Dues,450,,,\n")

    assert_equal 4, @source.accounting_records.current.where(role: "customer").count
    assert_equal 10_000, @source.accounting_records.find_by(role: "charge", number: "1042").balance_cents
    links = @source.accounting_customer_links.pluck(:customer_external_id, :person_id, :source)
    assert_includes links, [ "nancy.ward@example.com", @nancy.id, "reference" ]
    assert_includes links, [ ward.neat_id, ward.id, "reference" ]
    assert_not(links.any? { |customer, *| customer == "nancy ward" })

    customer = @source.accounting_records.find_by(role: "customer", customer_external_id: "nancy ward")
    suggestions = Accounting::CustomerLinks.new(@source).suggestions_for([ customer ])["nancy ward"]
    assert_equal [ [ @nancy, "name" ] ], suggestions.map { |suggestion| [ suggestion.person, suggestion.strategy ] }
  end

  test "a row missing from the next file is marked deleted, and an unchanged row isn't saved again" do
    apply(file_fixture("accounting/dues.csv").read)
    charge = @source.accounting_records.find_by(role: "charge", number: "1043")
    receipt = @source.accounting_records.find_by(role: "receipt")

    kept = file_fixture("accounting/dues.csv").read.lines.reject { |line| line.start_with?("Ward Family") }.join
    apply(kept)

    assert receipt.reload.deleted?
    assert @source.accounting_records.find_by(role: "customer", customer_external_id: "ward family").deleted?
    assert_equal charge.updated_at, charge.reload.updated_at
  end

  test "an applied upload is what a full sync reads, and the nightly job leaves file sources alone" do
    apply(file_fixture("accounting/dues.csv").read)
    assert_empty Accounting::Sync.new(@source).full

    with_accounting do
      travel_to(Date.new(2026, 11, 29).noon) do
        assert_no_enqueued_jobs(only: Accounting::FullSyncJob) { Accounting::NightlyJob.perform_now }
      end
    end
  end

  test "an upload with errors can't be applied, and the job only applies an upload sent to it" do
    upload = @source.accounting_uploads.new(content: file_fixture("accounting/problems.csv").read, created_by: @treasurer).read_content
    upload.save!
    assert upload.problems?
    assert_not upload.appliable?

    with_accounting { Accounting::ApplyUploadJob.perform_now(@source, upload) }
    assert_equal "previewed", upload.reload.status
    assert_empty @source.accounting_records
  end

  private
    def read(content)
      Accounting::Files::Reader.new(content).read
    end

    def apply(content)
      upload = @source.accounting_uploads.new(content: content, created_by: @treasurer).read_content
      assert_empty upload.row_errors
      upload.update!(status: "applying")
      with_accounting { Accounting::ApplyUploadJob.perform_now(@source, upload) }
      assert_equal "applied", upload.reload.status
      upload
    end
end
