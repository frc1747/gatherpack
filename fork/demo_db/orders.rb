# Fills an anonymized demo database with believable robotics purchasing, so
# Orders (and Inventory) can be seen and documented with real-looking data:
# vendors, funding sources, about 25 requests in every state, and a little
# stock. Run after personas.rb, with the orders flag on (the inventory and
# order-inventory parts run when those flags are on too).
#
#   bin/rails runner fork/demo_db/orders.rb
#
# Everything goes through the same model methods the screens use (submit,
# decide, buy, receive), run at backdated times over the last ten weeks, so
# timelines read as if people had done it. Running it again creates nothing
# new: requests are keyed by title and requester, vendors and funding sources
# by name, stock history is written once per item.
#
# People are picked by role: requesters are members of the teams below the
# top team who aren't on Mentors; approvers and buyers come from Mentors
# (managers first), then any team managers, then admins, whoever Orders lets
# do the job. On a database with no Mentors team (the Northwind sample data)
# that means managers and admins. See "Orders data" in fork/demo_db/README.md.
#
# Env: ORDERS_SAMPLE_DB=<database name> runs against a throwaway copy of the
# Northwind sample data instead of a *_demo database.
require_relative "guard"
require "active_support/testing/time_helpers"

# The guard for a throwaway sample copy: it must be named in the environment,
# be local, and look like Northwind. Never the real demo or production.
def guard_sample_db!(name)
  DemoDb.refuse("RAILS_ENV is production") if Rails.env.production?
  { ActiveRecord::Base => name, AbstractVersion => "#{name}_versions" }.each do |klass, expected|
    connection = klass.connection
    DemoDb.refuse("#{connection.current_database} isn't #{expected}") unless connection.current_database == expected
    DemoDb.refuse("#{expected} looks like production") if expected.include?("production")
    DemoDb.refuse("database host isn't local") unless DemoDb::LOCAL_HOSTS.include?(klass.connection_db_config.host.to_s)
    DemoDb.refuse("the server also holds gatherpack_production") if connection.select_value("select 1 from pg_database where datname = 'gatherpack_production'")
  end
  DemoDb.refuse("#{name} isn't the Northwind sample data") unless Team.exists?(name: "Northwind Community")
end

if ENV["ORDERS_SAMPLE_DB"].present?
  guard_sample_db!(ENV["ORDERS_SAMPLE_DB"])
else
  DemoDb.guard!
end

abort "fork/demo_db/orders: turn the Orders feature on first (Settings > Features)." unless GatherPack::Features.enabled?(:orders)
INVENTORY = GatherPack::Features.enabled?(:inventory) && defined?(Item) && Item.table_exists?
STOCK_LINKS = INVENTORY && defined?(OrderInventory) && OrderInventory.enabled?

module Backdate
  extend ActiveSupport::Testing::TimeHelpers
end

NOW = Time.current
TODAY = Date.current
Summary = Struct.new(:made, :skipped, :notes).new(0, [], [])

def say(label, value = nil)
  puts value.nil? ? "== #{label}" : "   #{label}: #{value}"
end

# Runs the block as if it were that many days ago (never in the future).
def at(days_ago, hour = 10, &block)
  moment = [ NOW.beginning_of_day - days_ago.days + hour.hours, NOW ].min
  Backdate.travel_to(moment, &block)
end

def cents(dollars)
  (dollars * 100).round
end

# -- People ---------------------------------------------------------------

top = Team.where(parent_id: nil).reject { |team| team.name == "Mentors" }.max_by { |team| team.all_descendant_ids.size }
abort "fork/demo_db/orders: no teams found." unless top
mentors_team = Team.find_by(name: "Mentors")
mentor_ids = mentors_team ? Membership.where(team_id: [ mentors_team.id ] + mentors_team.all_descendant_ids).pluck(:person_id).uniq : []
student_team_ids = top.all_descendant_ids - (mentors_team ? [ mentors_team.id ] + mentors_team.all_descendant_ids : [])
admin_people = Person.joins(:user).where(users: { admin: true }).order(:created_at, :id).to_a

# Students: on a team below the top team, not mentors, not admins.
students = Person.joins(:memberships).where(memberships: { team_id: student_team_ids }).distinct
  .reject { |person| mentor_ids.include?(person.id) || person.admin? }
persona_emails = %w[demo.member@example.invalid demo.student@example.invalid demo.lead@example.invalid]
personas = persona_emails.filter_map { |email| students.find { |person| person.user&.email == email } }
others = (students - personas).sort_by { |person| Digest::MD5.hexdigest(person.id) }.first(8)
requesters = personas + others
abort "fork/demo_db/orders: no students on the teams below #{top.name}." if requesters.empty?

# Approvers and buyers, in the order Orders is asked: mentors (managers
# first), else team managers, then admins.
manager_ids = Membership.where(manager: true).pluck(:person_id)
mentors = Person.where(id: mentor_ids).sort_by { |person| [ manager_ids.include?(person.id) ? 0 : 1, person.id ] }
staff = (mentors.presence || Person.where(id: manager_ids).where.not(id: students.map(&:id)).sort_by(&:id)) + admin_people
staff = staff.uniq
abort "fork/demo_db/orders: no mentors, managers or admins to approve and buy." if staff.empty?

# The team a request is made for: one of the requester's, not a leadership group.
team_for = lambda do |person|
  teams = person.teams.where(id: student_team_ids).order(:name).to_a
  teams.find { |team| team.name !~ /leadership/i } || teams.first || top
end

# -- Settings (only where blank) -------------------------------------------

mentor_badge = Badge.added_by_admin.where("name ILIKE ?", "%mentor%").to_a
  .max_by { |badge| BadgeAssignment.where(badge_id: badge.id, person_id: mentor_ids).count }
mentor_badge = nil if mentor_badge && BadgeAssignment.where(badge_id: mentor_badge.id, person_id: mentor_ids).none?
lead_badge = Badge.added_by_admin.find_by("name ILIKE ? OR name ILIKE ?", "%lead mentor%", "%mentor lead%")

# Approval steps are list rows; change them only while they're the untouched default.
Orders::Lists.seed!
steps = ApprovalStep.ordered.to_a
if steps.size == 1 && steps.first.key == "approval" && steps.first.approvers.none?
  first = steps.first
  first.update!(name: "Mentor approval")
  first.approvers.find_or_create_by!(badge: mentor_badge, team: top) if mentor_badge
  if lead_badge
    lead = ApprovalStep.create!(key: "lead_mentor", name: "From $500, also a lead mentor", minimum_cents: 50_000)
    lead.approvers.create!(badge: lead_badge, team: top)
  end
  say "Approval steps", ApprovalStep.active.ordered.map(&:name).join(" / ")
end
if Settings[:orders_buyers].blank? && mentor_badge
  Settings[:orders_buyers] = "#{mentor_badge.name} > #{top.name}"
  say "Buyers", Settings[:orders_buyers]
end
Orders::Current.reset
card = PaymentMethod.active.ordered.find { |method| !method.reimburse }
personal = PaymentMethod.active.ordered.find(&:reimburse)

# Who may do what, asked of Orders itself so the data is something the
# screens would allow. Falls through to an admin when a mentor doesn't reach
# the requester's team; the count is reported.
fallbacks = 0
pick = lambda do |&allowed|
  person = staff.find(&allowed)
  raise Orders::Refused, "none of #{staff.size} mentors, managers or admins may do this" unless person

  fallbacks += 1 if mentors.any? && mentors.exclude?(person)
  person
end
decider_for = ->(order_request) { pick.call { |person| order_request.can_decide?(person) } }
buyer_for = ->(order_request) { pick.call { |person| Orders::Access.for(person).buyer_for?(order_request.team_id) } }

# -- Vendors and funding ---------------------------------------------------

vendors = {
  wcp: [ "WCP - West Coast Products", "https://wcproducts.com", %w[wcproducts.com], "Team account, ships from California" ],
  rev: [ "REV Robotics", "https://www.revrobotics.com", %w[revrobotics.com], nil ],
  andymark: [ "AndyMark", "https://www.andymark.com", %w[andymark.com], nil ],
  mcmaster: [ "McMaster-Carr", "https://www.mcmaster.com", %w[mcmaster.com], "Ships the same day, tax exempt on file" ],
  amazon: [ "Amazon", "https://www.amazon.com", %w[amazon.com a.co], nil ],
  bambu: [ "Bambu Lab", "https://us.store.bambulab.com", %w[us.store.bambulab.com], nil ],
  ctr: [ "CTR Electronics", "https://store.ctr-electronics.com", %w[ctr-electronics.com], nil ],
  thrifty: [ "The Thrifty Bot", "https://www.thethriftybot.com", %w[thethriftybot.com], nil ]
}.transform_values do |name, website, domains, note|
  at(70) do
    vendor = Vendor.find_or_initialize_by(name: name)
    vendor.assign_attributes(website: website, domains: domains, preferred: true, active: true, account_note: note) if vendor.new_record?
    vendor.save!
    vendor
  end
end

fund = lambda do |name, **attributes|
  at(70) { FundingSource.find_by(name: name) || FundingSource.create!(name: name, team: top, active: true, **attributes) }
end
season = fund.call("Build season", kind: :general, amount_cents: cents(6000))
outreach = fund.call("Outreach", kind: :general, amount_cents: cents(800))
grant = fund.call("Parts grant (robot parts only)", kind: :restricted, amount_cents: cents(2500), starts_on: TODAY - 80, ends_on: TODAY + 200,
  restriction: "Robot parts only: drivetrain, mechanisms, motors and electronics. No tools, consumables, travel or food.",
  giver: "A regional robotics sponsor", reference: "Parts grant, current season")

# -- Inventory: places and items --------------------------------------------

stock_by = staff.first
items = {}
places = {}
if INVENTORY
  at(70) do
    Inventory::Lists.seed_defaults!
    place = lambda do |name, parent: nil, type: "storage", position: 0|
      Location.find_or_create_by!(name: name, parent_id: parent&.id, team_id: top.id) do |location|
        location.assign_attributes(location_type: LocationType.find_by!(key: type), position: position, active: true)
      end
    end
    shop = place.call("Shop")
    places[:shop] = shop
    places[:hardware] = place.call("Hardware cabinet", parent: shop, position: 1)
    places[:electronics] = place.call("Electronics shelf", parent: shop, position: 2)
    places[:motors] = place.call("Motor bin", parent: shop, position: 3)
    places[:practice] = place.call("Practice bot", parent: shop, type: "machine", position: 4)

    # key, name, category, maker, part number, unit, place, reorder at, reorder qty, starting count
    catalog = [
      [ :bolts, "10-32 x 0.5 in button head screw", "Fasteners", "McMaster-Carr", "92095A", "each", :hardware, 100, 200, 340 ],
      [ :nuts, "1/4-20 nylock nut", "Fasteners", "McMaster-Carr", "90631A", "each", :hardware, 100, 200, 60 ],
      [ :washers, "10 x 3/8 in flat washer", "Fasteners", "McMaster-Carr", "92141A", "each", :hardware, 100, 200, 410 ],
      [ :bearing, "WCP-0775 radial bearing, 0.250 x 0.500 x 0.188 in", "Bearings", "WCP", "WCP-0775", "each", :hardware, 12, 20, 28 ],
      [ :collars, "1/2 in hex shaft collar", "Bearings", "WCP", "WCP-0087", "each", :hardware, 8, 16, 16 ],
      [ :belts, "9 mm HTD 5M belt", "Belts", "WCP", "WCP-0184", "each", :hardware, 4, 8, 6 ],
      [ :shaft, "1/2 in hex shaft, 12 in", "Shafts", "McMaster-Carr", "9271T", "each", :hardware, 4, 8, 3 ],
      [ :zip_ties, "Zip ties, 8 in", "Consumables", "Generic", "ZT-8-100", "each", :hardware, 200, 500, 80 ],
      [ :petg_white, "PETG Basic filament, white", "Filament", "Bambu Lab", "G02-W0", "spool", :hardware, 2, 4, 3 ],
      [ :petg_black, "PETG Basic filament, black", "Filament", "Bambu Lab", "G02-K0", "spool", :hardware, 2, 4, 1 ],
      [ :anderson, "Anderson SB50 connector", "Electrical", "Anderson", "SB50", "each", :electronics, 10, 20, 38 ],
      [ :sparkmax, "SPARK MAX motor controller", "Electrical", "REV Robotics", "REV-11-2158", "each", :electronics, 2, 4, 3 ],
      [ :wire_red, "12 AWG wire, red", "Electrical", "Generic", "W12-RED", "foot", :electronics, 25, 50, 60 ],
      [ :wire_black, "12 AWG wire, black", "Electrical", "Generic", "W12-BLK", "foot", :electronics, 25, 50, 45 ],
      [ :tape, "Electrical tape", "Consumables", "Generic", "ET-BLK", "each", :electronics, 3, 6, 7 ]
    ]
    catalog.each do |key, name, category, maker, part, unit, home, point, quantity, start|
      item = Item.find_or_create_by!(name: name, team_id: top.id) do |new_item|
        new_item.assign_attributes(category: category, manufacturer: maker, manufacturer_part_number: part, unit: unit,
          home_location: places[home], reorder_point: point, reorder_quantity: quantity, active: true, tracked: false)
      end
      items[key] = item
      next if StockMovement.exists?(item_id: item.id)

      StockMovement.record!(kind: :added, item: item, location: item.home_location, quantity: start, person: stock_by, reason: "Starting count", authorized_by: stock_by)
    end

    { kraken: [ "Kraken X60 motor", "KRAKEN-X60" ], vortex: [ "NEO Vortex motor", "REV-21-1652" ] }.each do |key, (name, part)|
      item = Item.find_or_create_by!(name: name, team_id: top.id) do |new_item|
        new_item.assign_attributes(category: "Motors", manufacturer: name.split.first, manufacturer_part_number: part, unit: "each",
          home_location: places[:motors], reorder_point: 2, active: true)
      end
      item.start_tracking!(by: stock_by, authorized_by: stock_by) unless item.tracked?
      ItemUnit.receive!(item: item, location: places[:motors], count: 2, person: stock_by, note: "Starting count", authorized_by: stock_by) if item.item_units.none?
      items[key] = item
    end
  end
end

# -- Requests ---------------------------------------------------------------

line = lambda do |description, price, qty = 1, vendor: nil, item: nil, **attributes|
  vendor_id = vendors[vendor]&.id
  linked = items[item] if item && STOCK_LINKS
  { description: description, estimated_unit_price_cents: cents(price), quantity: qty, vendor_id: vendor_id, item: linked }.merge(attributes).compact
end

# Runs one step of a request's story, `day` days ago.
perform = lambda do |order_request, day, action, options|
  at(day, options.fetch(:hour, 10)) do
    order_request.reload
    lines = Array(options[:lines] == :all || options[:lines].nil? ? order_request.order_lines.to_a : options[:lines].map { |index| order_request.order_lines.to_a[index] })
    case action
    when :submit then order_request.submit!(by: order_request.requested_by)
    when :resubmit then order_request.resubmit!(by: order_request.requested_by, comment: options[:comment])
    when :approve
      4.times do
        break unless order_request.reload.submitted? || order_request.needs_reapproval?

        approver = decider_for.call(order_request)
        order_request.decide!(:approved, by: approver, comment: options[:comment], fits_restriction: order_request.restricted_sources.any?)
      end
    when :changes then order_request.decide!(:changes_requested, by: decider_for.call(order_request), comment: options.fetch(:comment))
    when :decline then order_request.decide!(:declined, by: decider_for.call(order_request), comment: options.fetch(:comment))
    when :buy
      buyer = buyer_for.call(order_request)
      vendor = vendors[options[:vendor]]
      prices = options.fetch(:prices, {}).transform_keys { |index| order_request.order_lines.to_a[index].id }
      reimburse = options[:paid] == :personal
      Orders::RecordPurchase.new(buyer: buyer, lines: lines, vendor: vendor, other_vendor_name: vendor ? nil : options[:other], prices: prices,
        attributes: { ordered_on: Date.current, vendor_order_number: options[:number], payment_method: reimburse ? personal : card,
                      reimburse_to: (buyer if reimburse), shipping_cents: cents(options.fetch(:shipping, 0)), tax_cents: cents(options.fetch(:tax, 0)),
                      expected_on: TODAY + options.fetch(:expected, 0) }).call
    when :backorder then lines.each { |each| each.backorder!(by: buyer_for.call(order_request), expected_on: TODAY + options.fetch(:expected, 7), comment: options[:comment]) }
    when :receive
      lines.each do |each|
        each.reload
        next unless each.open_to_receive?

        quantity = options[:quantity] || each.to_come_quantity
        params = {}
        receiver = order_request.requested_by
        if each.item && STOCK_LINKS && options.fetch(:condition, :good) == :good
          home = each.item.home_location
          receiver = staff.find { |person| Inventory::Access.for(person).sees?(home) } || admin_people.first || receiver
          params = { order_inventory: { put_away: "1", location_id: home.id } }
        end
        each.record_delivery!(by: receiver, quantity: quantity, received_on: Date.current, condition: options.fetch(:condition, :good),
          note: options[:note], params: params)
        Summary.notes.concat(OrderInventory::Current.problems.to_a.uniq) if STOCK_LINKS
      end
    when :close then order_request.close!(by: order_request.requested_by)
    else raise ArgumentError, "unknown step #{action}"
    end
  end
end

index = 0
scenario = lambda do |title, ago:, lines:, steps: [], needed: nil, purpose: nil, funding: season, team: nil, who: nil|
  requester = requesters[who || (index % requesters.size)]
  index += 1
  if OrderRequest.exists?(title: title, requested_by_id: requesters.map(&:id))
    next
  end

  ActiveRecord::Base.transaction do
    request_team = team || team_for.call(requester)
    order_request = at(ago) do
      OrderRequest.draft_for(person: requester, team: request_team, lines: lines, title: title,
        purpose: purpose, needed_by: (TODAY + needed if needed), funding_source: funding)
    end
    steps.each { |day, action, options| perform.call(order_request, day, action, options || {}) }
    Summary.made += 1
  end
rescue Orders::Refused, ActiveRecord::RecordInvalid => error
  Summary.skipped << "#{title}: #{error.message}"
end

say "Requests"
# 1. Closed: bought, put on the shelf, closed.
scenario.call("Swerve module fasteners", ago: 67, purpose: "Spares for the swerve modules before the first event.",
  lines: [ line.call("10-32 x 0.5 in button head screws, pack of 100", 11.84, 3, vendor: :mcmaster, item: :bolts, vendor_part_number: "92095A421", unit: "pack", units_per: 100),
           line.call("1/4-20 nylock nuts, pack of 100", 8.97, 2, vendor: :mcmaster, item: :nuts, vendor_part_number: "90631A029", unit: "pack", units_per: 100) ],
  steps: [ [ 66, :submit ], [ 65, :approve, { comment: "Good. We are low on both." } ], [ 63, :buy, { vendor: :mcmaster, number: "4417-12293", shipping: 6.5, tax: 0, expected: -60 } ],
           [ 59, :receive ], [ 45, :close ] ])

# 2. Closed: belts and pulleys, one vendor.
scenario.call("Drive belts and pulleys", ago: 63, purpose: "Belts for the practice drivetrain and one spare set.",
  lines: [ line.call("9 mm HTD 5M belt, 400 mm", 11.99, 4, vendor: :wcp, item: :belts, vendor_part_number: "WCP-0184", url: "https://wcproducts.com/products/htd-5m-belts"),
           line.call("15T HTD 5M pulley, 1/2 in hex", 14.99, 4, vendor: :wcp, vendor_part_number: "WCP-0242") ],
  steps: [ [ 62, :submit ], [ 61, :approve ], [ 58, :buy, { vendor: :wcp, number: "WCP-118842", shipping: 9.0, expected: -52 } ], [ 54, :receive ], [ 40, :close ] ])

# 3. Received: filament from Bambu Lab, labels from Amazon, two purchases (from the team's old form).
scenario.call("Filament and labels", ago: 58, purpose: "Prototype parts and labels for the parts bins.",
  lines: [ line.call("PETG Basic filament, white + black", 9.09, 2, vendor: :bambu, unit: "spool"),
           line.call("1x2 in direct thermal labels", 7.99, 1, vendor: :amazon, unit: "roll") ],
  steps: [ [ 57, :submit ], [ 56, :approve ], [ 54, :buy, { lines: [ 0 ], vendor: :bambu, number: "BL-77120", shipping: 4.99, expected: -50 } ],
           [ 54, :buy, { lines: [ 1 ], vendor: :amazon, number: "113-4410922-5602", expected: -51, hour: 11 } ], [ 50, :receive ] ])

# 4. Closed: office supplies from Amazon and another store, paid personally.
scenario.call("Office and CAD supplies", ago: 52, purpose: "Mice so the design team can use CAD on laptops, and envelopes for sponsor thank-you letters.",
  lines: [ line.call("Wired mouse (for CAD)", 9.99, 10, vendor: :amazon, url: "https://www.amazon.com/dp/B07R2YNY2Z"),
           line.call("No.10 white self-sealing envelopes, box of 100", 10.00, 1, other_vendor_name: "Office supply store", other_vendor_reason: "Needed this week and not sold in our size online", unit: "box") ],
  steps: [ [ 51, :submit ], [ 50, :approve ], [ 48, :buy, { lines: [ 0 ], vendor: :amazon, number: "113-9021177-1840", expected: -45 } ],
           [ 47, :buy, { lines: [ 1 ], other: "Office supply store", paid: :personal, number: "Receipt 1827" } ], [ 44, :receive ], [ 30, :close ] ])

# 5. Part of it bought: the bearings came, the shaft still waits for a buyer.
scenario.call("Intake bearings and shaft", ago: 47, purpose: "Intake rebuild: new bearings and a longer roller shaft.", needed: 12,
  lines: [ line.call("WCP-0775 radial bearing 0.250 in ID x 0.500 in OD x 0.188 in WD", 1.99, 10, vendor: :wcp, item: :bearing, vendor_part_number: "WCP-0775", manufacturer: "WCP", manufacturer_part_number: "WCP-0775"),
           line.call("1/2 in hex shaft, 12 in", 14.35, 4, vendor: :mcmaster, item: :shaft, vendor_part_number: "9271T21") ],
  steps: [ [ 46, :submit ], [ 45, :approve ], [ 43, :buy, { lines: [ 0 ], vendor: :wcp, number: "WCP-119207", shipping: 5.0, expected: -38 } ], [ 38, :receive, { lines: [ 0 ] } ] ])

# 6. Received: Kraken motors, over $500, so every approval step.
scenario.call("Kraken X60 motors for the shooter", ago: 44, purpose: "Four Kraken X60 motors for the shooter and a spare.", needed: -10, funding: grant,
  lines: [ line.call("Kraken X60 brushless motor", 219.99, 4, vendor: :ctr, item: :kraken, vendor_part_number: "KRAKEN-X60", url: "https://store.ctr-electronics.com/") ],
  steps: [ [ 43, :submit ], [ 41, :approve, { comment: "Approved from the parts grant." } ], [ 40, :buy, { vendor: :ctr, number: "CTR-55871", shipping: 12.0, tax: 0, expected: -33 } ], [ 34, :receive ] ])

# 7. Polycarbonate: arrived cracked (a problem for the buyer).
scenario.call("Bumper backing sheet", ago: 38, purpose: "Polycarbonate for the electronics panel and bumper backing.",
  lines: [ line.call("Polycarbonate sheet, 0.093 in thick, 12 x 24 in", 18.64, 3, vendor: :mcmaster, vendor_part_number: "8574K26") ],
  steps: [ [ 37, :submit ], [ 36, :approve ], [ 34, :buy, { vendor: :mcmaster, number: "4417-13310", shipping: 8.0, expected: -29 } ],
           [ 29, :receive, { quantity: 3, condition: :damaged, note: "One sheet arrived cracked in the box; the other two are fine." } ] ])

# 8. Backordered: batteries.
scenario.call("Competition batteries", ago: 34, purpose: "Fresh batteries before the district event.", needed: 14,
  lines: [ line.call("MK ES17-12 12V 17Ah battery", 28.00, 6, vendor: :andymark, vendor_part_number: "am-0477") ],
  steps: [ [ 33, :submit ], [ 32, :approve ], [ 30, :buy, { vendor: :andymark, number: "AM-208841", shipping: 18.0, tax: 0, expected: -20 } ], [ 21, :backorder, { expected: 9, comment: "AndyMark says the batteries ship next week." } ] ])

# 9. Partly received: zip ties (4 of 10 cases here), Anderson connectors in full.
scenario.call("Zip ties, tape and connectors", ago: 30, purpose: "Wiring supplies for two new robots.",
  lines: [ line.call("Zip ties, 8 in, bag of 100", 4.49, 10, vendor: :amazon, item: :zip_ties, unit: "bag", units_per: 100),
           line.call("Anderson SB50 connectors, 10 pack", 18.99, 2, vendor: :amazon, item: :anderson, unit: "pack", units_per: 10) ],
  steps: [ [ 29, :submit ], [ 28, :approve ], [ 26, :buy, { vendor: :amazon, number: "113-6620418-3319", expected: -22 } ],
           [ 21, :receive, { lines: [ 1 ] } ], [ 20, :receive, { lines: [ 0 ], quantity: 4, note: "Rest of the bags are still coming." } ] ])

# 10. Ordered: SPARK MAX controllers.
scenario.call("SPARK MAX controllers", ago: 21, purpose: "Controllers for the new mechanisms.", needed: 6,
  lines: [ line.call("SPARK MAX motor controller", 89.99, 4, vendor: :rev, item: :sparkmax, vendor_part_number: "REV-11-2158", url: "https://www.revrobotics.com/rev-11-2158/") ],
  steps: [ [ 20, :submit ], [ 19, :approve ], [ 17, :buy, { vendor: :rev, number: "REV-4482019", shipping: 8.5, expected: 3 } ] ])

# 11. A price went up after approval, so it needs approving again.
scenario.call("Elevator kit", ago: 19, purpose: "Elevator for the climber prototype.", needed: 20,
  lines: [ line.call("Thrifty Elevator kit", 249.99, 1, vendor: :thrifty, vendor_part_number: "TE-1") ],
  steps: [ [ 18, :submit ], [ 17, :approve ], [ 14, :buy, { vendor: :thrifty, number: "TTB-3071", prices: { 0 => cents(329.99) }, expected: 6 } ] ])

# 12. Ordered: Vortex motors.
scenario.call("NEO Vortex motors", ago: 16, purpose: "Two Vortex motors for the intake.",
  lines: [ line.call("NEO Vortex brushless motor", 199.99, 2, vendor: :rev, item: :vortex, vendor_part_number: "REV-21-1652", url: "https://www.revrobotics.com/rev-21-1652/") ],
  steps: [ [ 15, :submit ], [ 14, :approve ], [ 12, :buy, { vendor: :rev, number: "REV-4482977", shipping: 8.5, expected: 2 } ] ])

# 13. Received and put on the shelf: the grant buys drivetrain parts.
scenario.call("Drivetrain parts from the grant", ago: 22, funding: grant, purpose: "Drive parts for the new chassis.",
  lines: [ line.call("WCP-0775 radial bearing 0.250 in ID x 0.500 in OD x 0.188 in WD", 1.99, 20, vendor: :wcp, item: :bearing, vendor_part_number: "WCP-0775"),
           line.call("1/2 in hex shaft collar", 1.5, 16, vendor: :wcp, item: :collars, vendor_part_number: "WCP-0087") ],
  steps: [ [ 21, :submit ], [ 20, :approve ], [ 18, :buy, { vendor: :wcp, number: "WCP-120511", shipping: 6.0, expected: -10 } ], [ 11, :receive ] ])

# 14. Approved, waiting for a buyer.
scenario.call("Practice bot wiring", ago: 9, purpose: "Rewire the practice bot with proper connectors.", needed: 5,
  lines: [ line.call("12 AWG wire, red, 25 ft", 14.99, 2, vendor: :amazon, item: :wire_red, unit: "spool", units_per: 25),
           line.call("12 AWG wire, black, 25 ft", 14.99, 2, vendor: :amazon, item: :wire_black, unit: "spool", units_per: 25),
           line.call("Heat shrink assortment", 8.99, 1, vendor: :amazon) ],
  steps: [ [ 8, :submit ], [ 6, :approve ] ])

# 15. Approved, waiting, with a "Not sure" store.
scenario.call("Pit toolbox", ago: 8, purpose: "Tools for the pit crew's toolbox.", needed: 25,
  lines: [ line.call("Torque screwdriver set (something like the Wera one the other team had)", 79.00, 1),
           line.call("Hex key set, long arm, metric", 14.99, 2, vendor: :amazon) ],
  steps: [ [ 7, :submit ], [ 5, :approve ] ])

# 16. Waiting on approval, outreach money.
scenario.call("Outreach demo robot parts", ago: 5, funding: outreach, purpose: "Parts for the small robot we bring to school demos.", needed: 14,
  lines: [ line.call("REV Mini Control Hub kit", 69.99, 1, vendor: :rev), line.call("Anderson SB50 connectors, 10 pack", 18.99, 1, vendor: :amazon) ],
  steps: [ [ 4, :submit ] ])

# 17. Waiting on approval: one line, needed soon.
scenario.call("Dead blow hammer", ago: 4, purpose: "Pit repairs.", needed: 4,
  lines: [ line.call("Dead blow hammer, 16 oz", 16.95, 1, vendor: :amazon) ], steps: [ [ 4, :submit, { hour: 15 } ] ])

# 18. Waiting on approval: over $500.
scenario.call("Spare Kraken motors and CANivore", ago: 3, funding: grant, purpose: "Two spare motors and a CAN tool for the pit.", needed: 21,
  lines: [ line.call("Kraken X60 brushless motor", 219.99, 2, vendor: :ctr, vendor_part_number: "KRAKEN-X60"), line.call("CANivore USB to CAN FD adapter", 79.99, 1, vendor: :ctr) ],
  steps: [ [ 3, :submit ] ])

# 19. Waiting on approval: end mills, a link without a store set.
scenario.call("Router bits and end mills", ago: 2, purpose: "Cutting aluminium plates on the router.", needed: 10,
  lines: [ line.call("1/4 in carbide end mill, 2 flute", 22.40, 4, vendor: :mcmaster, vendor_part_number: "8873A33"),
           line.call("Cutting oil, 1 qt", 17.15, 1, vendor: :mcmaster, vendor_part_number: "1909K33") ],
  steps: [ [ 2, :submit ] ])

# 20. Changes requested.
scenario.call("Printer nozzles and filament", ago: 12, purpose: "Print farm supplies.",
  lines: [ line.call("Hardened steel nozzle, 0.4 mm", 11.99, 4, vendor: :bambu), line.call("PETG Basic filament", 9.09, 6, vendor: :bambu) ],
  steps: [ [ 11, :submit ], [ 10, :changes, { comment: "We have black and white. Which colors do you want for the other four spools?" } ] ])

# 21. Declined.
scenario.call("Wireless keyboards for the pit", ago: 40, purpose: "Keyboards for the pit laptops.",
  lines: [ line.call("Wireless keyboard and mouse combo", 29.99, 4, vendor: :amazon) ],
  steps: [ [ 39, :submit ], [ 38, :decline, { comment: "There are three spare keyboards in the cabinet. Ask there first." } ] ])

# 22. Declined: more than the season allows.
scenario.call("Air compressor for the pit", ago: 27, purpose: "Fill the pneumatics tank at events.",
  lines: [ line.call("Portable 6-gallon air compressor", 139.00, 1, vendor: :amazon) ],
  steps: [ [ 26, :submit ], [ 24, :decline, { comment: "Not in this season's budget. The pit is allowed a hand pump." } ] ])

# 23. Drafts.
scenario.call("Safety glasses restock", ago: 1, purpose: "We are down to a few pairs.",
  lines: [ line.call("Safety glasses, clear, box of 12", 23.99, 2, vendor: :amazon) ])
scenario.call("Spare belts for the competition robot", ago: 0,
  lines: [ line.call("9 mm HTD 5M belt, 400 mm", 11.99, 4, vendor: :wcp), line.call("Shaft collars, something that fits the 1/2 in hex shaft", 2.0, 8) ])

# 24. Machine shop supplies: received and put on a shelf, closed.
scenario.call("Machine shop supplies", ago: 33, purpose: "Consumables for the mill and lathe.",
  lines: [ line.call("10 x 3/8 in flat washers, pack of 100", 6.12, 3, vendor: :mcmaster, item: :washers, vendor_part_number: "92141A011", unit: "pack", units_per: 100),
           line.call("Threadlocker, blue, 50 ml", 21.40, 2, vendor: :mcmaster, vendor_part_number: "1274K12") ],
  steps: [ [ 32, :submit ], [ 31, :approve ], [ 29, :buy, { vendor: :mcmaster, number: "4417-13204", shipping: 6.5, expected: -25 } ], [ 24, :receive ], [ 9, :close ] ])

# 25. Filament and a printer part: approved with one vendor, bought, delivered in part.
scenario.call("Filament for the season", ago: 14, purpose: "Black and white spools for the print farm.", needed: -1,
  lines: [ line.call("PETG Basic filament, white", 9.09, 4, vendor: :bambu, item: :petg_white, unit: "spool"),
           line.call("PETG Basic filament, black", 9.09, 4, vendor: :bambu, item: :petg_black, unit: "spool") ],
  steps: [ [ 13, :submit ], [ 12, :approve ], [ 10, :buy, { vendor: :bambu, number: "BL-78841", shipping: 4.99, expected: -4 } ], [ 5, :receive, { lines: [ 0 ], note: "The black spools are still coming." } ] ])

# -- Inventory: motors as tracked units ------------------------------------

if INVENTORY
  say "Units"
  at(10) do
    { kraken: "KX", vortex: "NV" }.each do |key, prefix|
      item = items[key]
      # Units that came on orders arrive unlabelled; label them in order and
      # give a few a condition. Labelled units are left as they are.
      fresh = item.item_units.where(code: nil).order(:created_at, :id).to_a
      fresh.each_with_index do |unit, number|
        unit.update!(code: format("%s-%02d", prefix, item.item_units.where.not(code: nil).count + 1))
        unit.check!(by: stock_by, condition: "good", authorized_by: stock_by) if number.even?
      end
      next if fresh.empty?

      if key == :vortex
        fresh.first.reload.check!(by: stock_by, condition: "worn", note: "Chewed splines on the output shaft", authorized_by: stock_by)
        fresh.last.reload.install!(into: places[:practice], by: stock_by, authorized_by: stock_by)
      else
        fresh.second.reload.mark_for_repair!(by: stock_by, note: "Runs hot at low load", authorized_by: stock_by)
      end
    end
  end
end

# -- Summary ----------------------------------------------------------------

say "Orders data"
say "requests made now", Summary.made
say "requests in all", OrderRequest.group(:status).count.sort.map { |status, count| "#{status} #{count}" }.join(", ")
say "lines", OrderLine.group(:status).count.sort.map { |status, count| "#{status} #{count}" }.join(", ")
say "purchases", Purchase.count
say "vendors", vendors.values.map(&:name).join(", ")
say "funding sources", [ season, outreach, grant ].map(&:name).join(", ")
say "decided or bought by someone outside Mentors", fallbacks if mentors.any? && fallbacks.positive?
say "items", "#{items.size} (#{Item.where(team_id: top.id).count} in all)" if INVENTORY
say "units", ItemUnit.count if INVENTORY
Summary.skipped.each { |message| say "skipped", message }
Summary.notes.uniq.each { |message| say "stock note", message }
