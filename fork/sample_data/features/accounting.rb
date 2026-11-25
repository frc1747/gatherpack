require "csv"

# Account status from a file source, so every accounting screen works with
# no outside account. Dates move with the clock on every load.
#
# Source: "Northwind dues sheet", a file source with one applied upload of
# $300 Dues charges.
#   Ava Smith       paid in full
#   Ben Smithers    partly paid ($200 left)
#   Chloe Smithson  nothing paid, due 10 days ago
#   Grace Miller    partly paid ($200 left), so her guardian Paula
#                   (parent1@) has something to see on Home and Family
#   Dan Jones       a payment and a scholarship credit, $50 left; his row
#                   names him rather than giving his id, so he waits under
#                   "Needs a link" on the Customers page with a suggestion
# Ava, Ben, Chloe and Grace are given by GatherPack id, so they link automatically.
#
# Rules (Account Status, each member's Account tab and statement):
#   "<season> Dues"     balance; the person and their guardians see status
#                       and amounts. Milestones "Deposit" ($200 owing at
#                       most) 10 days ago and "Paid in full" 20 days ahead.
#                       Ava Paid, Ben and Grace Partly paid, Chloe Overdue until her
#                       payment plan (below), everyone else Not invoiced.
#   "Paid this season"  amount paid, admins only: a treasurer's total.
#
# Actions on "<season> Dues": the admin-assigned "Dues Paid" badge while
# Paid (Ava), and a hidden "Dues" choice field (admins write, family reads)
# filled with the status in the rule's words, which a checklist item can
# test.
#
# Payment plan and reminders on "<season> Dues": Chloe on a two-payment plan
# ("First payment", $200 owing at most, 5 days ahead; "Last payment" 35 days
# ahead), so she is Not yet paid instead of Overdue. She and her guardians
# see the plan's milestones; leaders see only "On schedule"; admins see "On
# a plan", the note and the On a plan filter. Reminders go 5 days before
# each milestone, then every 7 days while overdue, to the person and their
# guardians, with the name and status (no email goes out without an email
# gateway).
#
# Billing: one finished run, "Next season's dues", $300 each, invoiced 30
# days ahead and due 60 days ahead. Ava, Ben and Chloe are in its CSV (Download
# CSV on the run page gives three charge rows in the template layout); Kate
# is skipped, "No customer", since nobody links her to the sheet and a file
# source can't make customers.
Hbr::SampleData.feature "feature/accounting" do |s|
  s.enable_feature :accounting
  s.enable_feature :person_fields

  admin = s.login(:admin)
  ava, ben, chloe, grace, kate = %w[Ava Ben Chloe Grace Kate].map { |first| s.person(first) }
  date = ->(days) { (days.negative? ? s.clock.days_ago(-days) : s.clock.days_from_now(days)).to_date.iso8601 }
  season_end = s.clock.season.last
  season = "#{season_end.year - 1}-#{format("%02d", season_end.year % 100)}"

  # The file source and its upload.
  csv = <<~CSV
    customer,role,number,date,due_date,item,total,balance,applied_to,description
    #{ava.neat_id},charge,D-101,#{date.call(-40)},#{date.call(20)},Dues,300.00,,,
    #{ben.neat_id},charge,D-102,#{date.call(-40)},#{date.call(20)},Dues,300.00,,,
    #{chloe.neat_id},charge,D-103,#{date.call(-40)},#{date.call(-10)},Dues,300.00,,,
    Dan Jones,charge,D-104,#{date.call(-40)},#{date.call(20)},Dues,300.00,,,
    #{grace.neat_id},charge,D-105,#{date.call(-40)},#{date.call(20)},Dues,300.00,,,
    #{ava.neat_id},payment,P-201,#{date.call(-30)},,,300.00,,D-101,Check 1001
    #{ben.neat_id},payment,P-202,#{date.call(-25)},,,100.00,,D-102,Check 1002
    #{grace.neat_id},payment,P-204,#{date.call(-12)},,,100.00,,D-105,Check 1004
    Dan Jones,payment,P-203,#{date.call(-20)},,,200.00,,D-104,Online payment
    Dan Jones,credit,C-301,#{date.call(-15)},,,50.00,,D-104,Hardship scholarship
  CSV

  source = s.upsert!(Gateway::FileSource, { name: "Northwind dues sheet" })
  upload = s.upsert!(AccountingUpload, { gateway: source, filename: "northwind-dues.csv" }, content: csv, created_by: admin)
  upload.read_content
  upload.update!(status: "applying", applied_by: admin)
  Accounting::ApplyUploadJob.perform_now(source, upload)

  s.report "file source with 5 Dues charges (paid, partly paid, overdue, credit and payment)"
  s.expect("the upload applied with no row errors") { upload.reload.status == "applied" && upload.row_errors.empty? }
  s.expect("Ava, Ben, Chloe and Grace are linked by id") do
    source.accounting_customer_links.where(source: "reference").pluck(:person_id).sort == [ ava, ben, chloe, grace ].map(&:id).sort
  end
  s.expect("Ben and Grace owe $200 and Dan $50") do
    balances = source.accounting_records.current.where(role: "charge").pluck(:number, :balance_cents).to_h
    balances == { "D-101" => 0, "D-102" => 20_000, "D-103" => 30_000, "D-104" => 5000, "D-105" => 20_000 }
  end

  # Rules.
  dues = s.upsert!(AccountingRule, { key: "sample_dues" },
    name: "#{season} Dues", gateway: source, kind: "balance", team: s.team(:root),
    description: "$100 by the deposit date, the rest by the end of the month.",
    read_permission: "family", amount_permission: "family", enabled: true)
  dues.milestones.delete_all
  dues.milestones.create!(name: "Deposit", due_on: s.clock.date(-10), balance_at_most_cents: 20_000, position: 0)
  dues.milestones.create!(name: "Paid in full", due_on: s.clock.date(20), balance_at_most_cents: 0, position: 1)
  # Chloe's plan is made again below; without it she follows the rule.
  dues.person_milestones.where(person: chloe).destroy_all

  paid = s.upsert!(AccountingRule, { key: "sample_paid_this_season" },
    name: "Paid this season", gateway: source, kind: "amount", measure: "paid",
    read_permission: "admin", amount_permission: "admin", enabled: true)

  [ dues, paid ].each { |rule| Accounting::Evaluation.new(rule).run }

  s.report "2 rules: #{dues.name} (balance, family) and #{paid.name} (amount, admins)"
  s.expect("Ava paid, Ben and Grace partly paid, Chloe overdue") do
    dues.results.where(person: [ ava, ben, chloe, grace ]).to_h { |result| [ result.person_id, result.value ] } ==
      { ava.id => "paid", ben.id => "partial", chloe.id => "overdue", grace.id => "partial" }
  end
  s.expect("everyone else in Northwind is Not invoiced") { dues.results.where(value: "not_invoiced").exists? }

  # Actions.
  badge = s.upsert!(Badge, { name: "Dues Paid" }, badge_type: BadgeType.find_or_create_by!(name: "Award"), team: nil,
    permission: "added_by_admin", color: "#2ec27e", short: "dollar-sign")
  field = s.upsert!(PersonField, { key: "dues_status" }, name: "Dues", data_type: :select,
    options: { "choices" => [ "Paid", "Partly paid", "Not yet paid", "Overdue", "Not invoiced" ] },
    read_permission: "family", write_permission: "admin", show_on_profile: false)

  dues.actions.delete_all
  dues.actions.create!(action: "badge", badge: badge, condition: { "values" => [ "paid" ] }, position: 0)
  dues.actions.create!(action: "person_field", person_field: field, write: "label", position: 1)
  Accounting::Evaluation.new(dues).run

  s.report "2 actions on #{dues.name}: Dues Paid badge while Paid, and the Dues field"
  s.expect("Ava has Dues Paid; Ben and Chloe don't") do
    BadgeAssignment.where(badge: badge).pluck(:person_id).include?(ava.id) &&
      !BadgeAssignment.where(badge: badge, person: [ ben, chloe ]).exists?
  end
  s.expect("the Dues field reads Paid, Partly paid, Overdue") do
    [ ava, ben, chloe ].map { |person| person.reload.field_value(field) } == [ "Paid", "Partly paid", "Overdue" ]
  end

  # Payment plan and reminders.
  dues.update!(remind_days_before: 5, overdue_every_days: 7, remind_to: "both", reminder_level: "name_only")
  dues.person_milestones.create!(person: chloe, name: "First payment", due_on: s.clock.date(5), balance_at_most_cents: 20_000,
    position: 0, note: "Agreed with the family by phone: two payments.", created_by: admin)
  dues.person_milestones.create!(person: chloe, name: "Last payment", due_on: s.clock.date(35), balance_at_most_cents: 0,
    position: 1, created_by: admin)
  Accounting::Evaluation.new(dues).run

  s.report "#{dues.name}: Chloe on a 2-payment plan; reminders 5 days before each milestone, every 7 days overdue"
  s.expect("Chloe is on her plan and no longer overdue") do
    result = dues.results.find_by(person: chloe)
    result&.on_plan? && result.value == "unpaid" && result.detail(:next)&.fetch("name") == "First payment"
  end
  s.expect("Ben still follows the rule's milestones") { !dues.results.find_by(person: ben)&.on_plan? }

  # Billing.
  memo = "Next season's dues"
  links = Accounting::CustomerLinks.new(source)
  source.accounting_billing_runs.where(memo: memo).destroy_all
  run = source.accounting_billing_runs.new(created_by: admin, item_external_id: "dues", amount_cents: 30_000, memo: memo,
    txn_date: s.clock.date(30), due_on: s.clock.date(60), status: "running")
  [ ava, ben, chloe ].each do |person|
    run.lines.build(person: person, customer_external_id: links.customer_ids_for(person).first, amount_cents: 30_000, status: "exported")
  end
  run.lines.build(person: kate, amount_cents: 30_000, status: "skipped", error: "No customer")
  run.save!
  run.finish_if_done!

  s.report "billing run on #{source.name}: 3 charges in the CSV, 1 skipped"
  s.expect("the run is finished with 3 exported and 1 skipped") do
    run.reload.finished? && run.details.slice("exported", "skipped") == { "exported" => 3, "skipped" => 1 }
  end
  s.expect("the CSV has a charge row for each of Ava, Ben and Chloe") do
    CSV.parse(Accounting::Files::BillingExport.new(run).csv).drop(1).map { |row| row[1] } == %w[charge charge charge]
  end
end
