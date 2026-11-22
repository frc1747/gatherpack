# Sample data for feature/orders.
#
# Operations buys for its crews. Henry holds Order Approver and Ruby
# Treasurer (the second step, from $500); Gina holds Order Buyer and Frank
# Funding Manager; steps Approval and Treasurer (from $500) are list rows,
# and Petty cash is a retired payment method on one purchase. They're on Operations (Ruby on Northwind Community) so
# their grants reach the crews. Requests come from Facilities and Logistics
# members, one in each state the spec lists (§8):
#
# - Paint rollers: a draft (Ella).
# - Ladder: waiting on the first step, with a "Not sure" line.
# - Pressure washer: over $500; Henry approved, waiting on the Treasurer.
# - Extension cords: changes requested.
# - Leaf blower: declined.
# - Shelving and bins: approved, two vendors; the shelf is bought (a little
#   over its estimate, within the tolerance), the bins wait for a buyer.
# - Safety glasses and Work gloves: one Hardware Barn purchase for both; the
#   gloves are backordered with an expected date.
# - Zip ties: 4 of 10 here.
# - Folding tables: delivered damaged, a problem for Gina.
# - Trash bags: received in full and closed; its line was moved to the
#   petty cash source after purchase.
# - Garden hose: an "Other store" line.
# - Floor fan: bought well over its estimate, so it needs re-approval.
# - Tool kit: split between the tools grant and the operations budget.
# - Power tools: more than the tools grant has left.
#
Hbr::SampleData.feature "feature/orders" do |s|
  s.enable_feature :orders
  root = s.team(:root)
  operations = s.team(:operations)
  facilities = s.team(:facilities)
  logistics = s.team(:logistics)
  award = BadgeType.find_or_create_by!(name: "Award")

  grant = lambda do |name, short, holder|
    badge = s.upsert!(Badge, { name: name }, badge_type: award, team: nil, permission: "added_by_admin", color: "#865e3c", short: short)
    BadgeAssignment.find_or_create_by!(badge: badge, person: holder)
    badge
  end
  henry, ruby, gina, frank = %w[Henry Ruby Gina Frank].map { |first| s.person(first) }
  [ henry, gina, frank ].each { |person| s.member!(person, operations) }
  s.member!(ruby, root)
  grant.call("Order Approver", "stamp", henry)
  grant.call("Treasurer", "coins", ruby)
  grant.call("Order Buyer", "credit-card", gina)
  grant.call("Funding Manager", "hand-holding-dollar", frank)

  # Approval steps and payment methods are lists (Setup > Orders and Inventory).
  Orders::Lists.seed!
  approval = s.upsert!(ApprovalStep, { key: "approval" }, name: "Approval", minimum_cents: 0, position: 0, active: true)
  treasurer = s.upsert!(ApprovalStep, { key: "treasurer" }, name: "Treasurer", minimum_cents: 50_000, position: 1, active: true)
  { approval => "Order Approver", treasurer => "Treasurer" }.each do |step, badge_name|
    step.approvers.find_or_create_by!(badge: Badge.find_by!(name: badge_name), team: root)
  end
  team_card = PaymentMethod.find_by!(name: "Team card")
  # A retired method still on an old purchase (retired after the scenarios).
  petty_cash = s.upsert!(PaymentMethod, { name: "Petty cash" }, reimburse: false, active: true)
  s.setting :orders_buyers, "Order Buyer > #{root.name}"
  s.setting :orders_funding_managers, "Funding Manager > #{root.name}"
  s.setting :orders_price_tolerance, "10%, 25"
  Orders::Current.reset

  parts = s.upsert!(Vendor, { name: "Parts Depot" }, website: "https://partsdepot.example", domains: [ "partsdepot.example" ],
    part_number_pattern: "/p/([A-Z0-9-]+)", preferred: true, active: true, account_note: "Customer 44120, tax exempt on file")
  hardware = s.upsert!(Vendor, { name: "Hardware Barn" }, website: "https://hardwarebarn.example", domains: [ "hardwarebarn.example" ],
    preferred: true, active: true)
  office = s.upsert!(Vendor, { name: "Office Supply Co" }, website: "https://officesupply.example", domains: [ "officesupply.example" ],
    preferred: true, active: true)
  s.upsert!(Vendor, { name: "Old Electronics" }, website: "https://oldelectronics.example", domains: [ "oldelectronics.example" ],
    preferred: false, active: false)

  budget = s.upsert!(FundingSource, { name: "Operations Budget" }, team: operations, kind: :general, amount_cents: 500_000,
    starts_on: s.clock.season[0].to_date, ends_on: s.clock.season[1].to_date, active: true)
  petty = s.upsert!(FundingSource, { name: "Facilities Petty Cash" }, team: facilities, kind: :general, amount_cents: nil, active: true)
  tools_grant = s.upsert!(FundingSource, { name: "Community Tools Grant" }, team: operations, kind: :restricted, amount_cents: 150_000,
    starts_on: s.clock.date(-60), ends_on: s.clock.date(240), report_due_on: s.clock.date(270), active: true,
    restriction: "Hand and power tools for the community workshop. No consumables, food or travel.",
    giver: "A local community foundation", reference: "Grant 2026-17")

  ella, isla, mia, quinn, uma, noah, jack = %w[Ella Isla Mia Quinn Uma Noah Jack].map { |first| s.person(first) }
  line = ->(description, price, quantity = 1, **attrs) { { description: description, estimated_unit_price_cents: (price * 100).round, quantity: quantity }.merge(attrs) }

  # Builds a request once, by title; later runs leave it as it is.
  made = 0
  scenario = lambda do |title, person, team, lines, **attrs, &block|
    next OrderRequest.find_by(title: title) if OrderRequest.exists?(title: title)

    made += 1
    order_request = OrderRequest.draft_for(person: person, team: team, lines: lines, title: title, **attrs)
    block&.call(order_request)
    order_request.reload
  end
  submit = ->(order_request) { order_request.submit!(by: order_request.requested_by) }
  approve = lambda do |order_request, fits: false|
    submit.call(order_request)
    order_request.reload.decide!(:approved, by: henry, fits_restriction: fits)
    order_request.reload
    order_request.decide!(:approved, by: ruby, fits_restriction: fits) if order_request.reload.submitted?
    order_request.reload
  end
  buy = lambda do |lines, vendor, prices: {}, **attrs|
    Orders::RecordPurchase.new(buyer: gina, lines: lines, vendor: vendor, other_vendor_name: vendor ? nil : attrs.delete(:other_vendor_name),
      prices: prices, attributes: { ordered_on: s.clock.date(-5), payment_method: team_card, expected_on: s.clock.date(4) }.merge(attrs)).call
  end

  scenario.call("Paint rollers", ella, facilities, [ line.call("9 in paint rollers", 4, 6, vendor_id: hardware.id) ])

  scenario.call("Ladder", isla, facilities,
    [ line.call("6 ft step ladder", 89, 1, vendor_id: hardware.id, url: "https://hardwarebarn.example/ladders/6ft"),
      line.call("Ladder stabilizer, something like the one in the shed", 30) ],
    needed_by: s.clock.date(10), purpose: "The old ladder has a cracked rung.", &submit)

  scenario.call("Pressure washer", mia, facilities, [ line.call("Electric pressure washer", 649, 1, vendor_id: hardware.id) ],
    purpose: "Cleaning the patio before the spring workday.", funding_source: budget) do |order_request|
    submit.call(order_request)
    order_request.reload.decide!(:approved, by: henry, comment: "Fine by me; over $500 so it goes to the Treasurer.")
  end

  scenario.call("Extension cords", quinn, facilities, [ line.call("Extension cord", 25, 4, vendor_id: hardware.id) ]) do |order_request|
    submit.call(order_request)
    order_request.reload.decide!(:changes_requested, by: henry, comment: "Which length? We have two 50 ft ones already.")
  end

  scenario.call("Leaf blower", uma, facilities, [ line.call("Gas leaf blower", 180, 1, vendor_id: hardware.id) ]) do |order_request|
    submit.call(order_request)
    order_request.reload.decide!(:declined, by: henry, comment: "We borrow the city's blower in the fall.")
  end

  scenario.call("Shelving and bins", noah, logistics,
    [ line.call("Steel shelving unit", 120, 1, vendor_id: parts.id, vendor_part_number: "SH-4818", url: "https://partsdepot.example/p/SH-4818"),
      line.call("Stacking bins", 6, 12, vendor_id: office.id) ],
    needed_by: s.clock.date(14), funding_source: budget) do |order_request|
    approve.call(order_request)
    shelf = order_request.order_lines.first
    buy.call([ shelf ], parts, prices: { shelf.id => 13_200 }, vendor_order_number: "PD-88213")
  end

  glasses = scenario.call("Safety glasses", jack, logistics, [ line.call("Safety glasses", 5, 10, vendor_id: hardware.id) ], &approve)
  gloves = scenario.call("Work gloves", ella, facilities, [ line.call("Work gloves, large", 8, 6, vendor_id: hardware.id) ],
    funding_source: petty, &approve)
  if glasses.approved? && gloves.approved?
    buy.call(glasses.order_lines + gloves.order_lines, hardware, vendor_order_number: "HB-5531", shipping_cents: 900, tax_cents: 650)
    gloves.order_lines.first.reload.backorder!(by: gina, expected_on: s.clock.date(12))
  end

  scenario.call("Zip ties", isla, facilities, [ line.call("Zip ties, pack of 100", 7, 10, vendor_id: hardware.id, unit: "pack", units_per: 100) ]) do |order_request|
    approve.call(order_request)
    buy.call(order_request.order_lines.to_a, hardware, vendor_order_number: "HB-5540")
    order_request.order_lines.first.reload.record_delivery!(by: isla, quantity: 4, received_on: s.clock.date(-1))
  end

  scenario.call("Folding tables", mia, facilities, [ line.call("6 ft folding table", 60, 2, vendor_id: office.id) ]) do |order_request|
    approve.call(order_request)
    buy.call(order_request.order_lines.to_a, office, vendor_order_number: "OS-1207", payment_method: petty_cash)
    order_request.order_lines.first.reload.record_delivery!(by: mia, quantity: 2, condition: :damaged,
      note: "One table has a bent leg; both boxes were crushed.")
  end

  scenario.call("Trash bags", quinn, facilities, [ line.call("Contractor trash bags", 25, 2, vendor_id: hardware.id) ],
    funding_source: budget) do |order_request|
    approve.call(order_request)
    buy.call(order_request.order_lines.to_a, hardware, vendor_order_number: "HB-5402", ordered_on: s.clock.date(-30))
    order_request.order_lines.first.reload.reallocate_funding!(petty, by: frank, reason: "Petty cash covers cleaning supplies.")
    order_request.reload.mark_all_received!(by: quinn, received_on: s.clock.date(-25))
    order_request.reload.close!(by: quinn)
  end

  scenario.call("Garden hose", uma, facilities,
    [ line.call("50 ft garden hose", 35, 1, other_vendor_name: "Corner Hardware", other_vendor_reason: "Open on Sundays") ], &submit)

  scenario.call("Floor fan", jack, logistics, [ line.call("Shop floor fan", 80, 1, vendor_id: parts.id) ]) do |order_request|
    approve.call(order_request)
    fan = order_request.order_lines.first
    buy.call([ fan ], parts, prices: { fan.id => 14_900 }, vendor_order_number: "PD-88290")
  end

  scenario.call("Tool kit", noah, logistics,
    [ line.call("Socket set", 140, 1, vendor_id: parts.id, funding_source_id: tools_grant.id),
      line.call("Shop rags", 12, 2, vendor_id: parts.id) ],
    funding_source: budget, purpose: "The workshop's shared tool kit.") { |order_request| approve.call(order_request, fits: true) }

  scenario.call("Power tools", noah, logistics,
    [ line.call("Cordless drill and driver kit", 299, 2, vendor_id: parts.id), line.call("Circular saw", 189, 2, vendor_id: parts.id),
      line.call("Spare batteries", 99, 4, vendor_id: parts.id) ],
    funding_source: tools_grant, purpose: "Power tools for the workshop.", needed_by: s.clock.date(20), &submit)


  # Ledger and Budget rows (spec §6, §8).
  # Operations keeps an "Operations Account" ledger. This season's Operations
  # Budget ($5,000) and Community Tools Grant ($1,500) budgets each carry their
  # own ledger tag, and the funding sources of the same names are linked to
  # them, so the approve screen shows each Budget's amount and its ledger
  # spending (which includes the workshop insurance, paid outside orders).
  #
  # Gina can't add ledger entries, so her purchases start "Not in ledger".
  # Adam (admin) recorded two of them later:
  # - Shelving and bins (PD-88213): one entry, tagged Operations, so it counts
  #   against the Operations Budget.
  # - Safety glasses and Work gloves (HB-5531): a split entry, one part for
  #   Facilities Petty Cash and one for the glasses, which have no source.
  # The rest (HB-5540 zip ties, OS-1207 tables, HB-5402 trash bags, PD-88290
  # fan) are "Not in ledger" for a treasurer to add.
  s.enable_feature :ledger
  s.enable_feature :budgets
  adam = s.login(:admin)

  account = s.upsert!(Ledger, { name: "Operations Account" }, team: operations)
  operations_tag = s.upsert!(LedgerTag, { name: "Operations" }, color: "#1c71d8")
  grant_tag = s.upsert!(LedgerTag, { name: "Tools Grant" }, color: "#26a269")
  season = s.upsert!(BudgetPeriod, { name: "Operations #{s.clock.season[0].year}–#{s.clock.season[1].year}", team: operations },
    starts_at: s.clock.season[0].beginning_of_day, ends_at: s.clock.season[1].end_of_day)
  link_budget = lambda do |source, tag, amount_cents|
    ledger_budget = Budget.joins(:budget_taggings).find_by(budget_period: season, budget_taggings: { ledger_tag_id: tag.id }) ||
      Budget.create!(budget_period: season, amount_cents: amount_cents)
    ledger_budget.update!(amount_cents: amount_cents)
    BudgetTagging.find_or_create_by!(budget: ledger_budget, ledger_tag: tag)
    source.link_budget!(ledger_budget) unless source.budget_id == ledger_budget.id
    ledger_budget
  end
  operations_budget = link_budget.call(budget, operations_tag, 500_000)
  link_budget.call(tools_grant, grant_tag, 150_000)

  insurance = s.upsert!(LedgerEntry, { ledger: account, remark: "Workshop insurance, spring" },
    amount_cents: -45_000, finalized: true, approved: true, created_by: adam.user)
  LedgerTagging.find_or_create_by!(ledger_entry: insurance, ledger_tag: operations_tag)

  %w[PD-88213 HB-5531].each do |number|
    purchase = Purchase.find_by(vendor_order_number: number)
    next if purchase.nil? || purchase.ledger_entry_id

    Orders::RecordInLedger.new(purchase, ledger: account, by: adam).call
  end

  s.expect("the shelving purchase counts against the Operations Budget") do
    entry = Purchase.find_by(vendor_order_number: "PD-88213")&.ledger_entry
    entry && entry.ledger_tags.include?(operations_tag) && Budget.find(operations_budget.id).ledger_entries.map(&:id).include?(entry.id)
  end
  s.expect("the glasses and gloves purchase is a split entry") do
    Purchase.find_by(vendor_order_number: "HB-5531")&.ledger_entry&.child_entries&.size == 2
  end
  s.expect("Gina can't add ledger entries, so her purchases wait for a treasurer") do
    Orders::LedgerRecording.ledgers_for(gina).empty? && Purchase.where(ledger_entry_id: nil).exists?
  end
  s.report "#{Purchase.where.not(ledger_entry_id: nil).count} purchases in the Operations Account, " \
    "#{Purchase.where(ledger_entry_id: nil).count} not in ledger"

  petty_cash.retire!

  s.report "#{made} order requests (#{OrderRequest.count} in all), #{Purchase.count} purchases, 4 vendors, 3 funding sources"
  s.expect("every request state is present") do
    %w[draft submitted changes_requested approved ordering declined closed].all? { |status| OrderRequest.where(status: status).exists? }
  end
  s.expect("a line needs re-approval") { OrderLine.needs_reapproval.exists? }
  s.expect("a line is backordered, one partly received and one a problem") do
    OrderLine.backordered.exists? && OrderLine.partly_received.exists? && OrderLine.problem.exists?
  end
  s.expect("a retired payment method is still on an old purchase") { Purchase.where(payment_method: petty_cash).exists? && !petty_cash.reload.active? }
  s.expect("the tools grant is over its amount with Power tools") do
    power = OrderRequest.find_by(title: "Power tools")
    tools_grant.numbers.over_after?(power)
  end
end
