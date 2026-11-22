# Emails to inventory managers (inventory spec §3.12), sent like the other
# GatherPack notices: one SendEmailJob per recipient through the email
# gateway, so no one sees anyone else's address, and nothing is sent (but
# nothing fails) when no gateway is set up. Nothing is sent while inventory
# is turned off. Members get no notices.
#
# Recipients for an item are the inventory managers within reach of its
# team: the people an inventory_managers row (Inventory::Reach) applies to
# for it. Admins aren't added for being admins. Each one hears the way
# they chose (Inventory::Config.notice_for): "each" gets the emails here as
# things happen, "daily" and "weekly" the digest, "off" nothing.
class InventoryNotices
  include ERB::Util

  # The people who hear about a team's items, narrowed to those whose
  # notice choice is one of notices.
  def self.recipients_for(team_id, notices: Inventory::Config::REORDER_NOTICES)
    managers.select do |person, team_ids|
      team_ids.include?(team_id) && Array(notices).include?(Inventory::Config.notice_for(person))
    end.keys
  end

  # { person => Set of team ids whose inventory notices they get }.
  def self.managers
    reach = Inventory::Config.managers
    reach.holders.to_a.to_h { |person| [ person, reach.granted_team_ids(person).to_set ] }.reject { |_person, team_ids| team_ids.empty? }
  end

  # An item went onto the reorder list.
  def running_low(item)
    total = item.total_stock
    deliver(self.class.recipients_for(item.team_id, notices: "each"), "Running low: #{item.name}") do
      "<p><strong>#{h(item.name)}</strong> is running low: #{h(item.stock_unit.quantity_text(total))} left, " \
        "order more at #{item.reorder_point}.</p>#{reorder_link}"
    end
  end

  # A count changed the stock a lot (Inventory::Digest.big_difference?).
  def count_differs(movement)
    return 0 unless Inventory::Digest.big_difference?(movement)

    item = movement.item
    deliver(self.class.recipients_for(item.team_id, notices: "each"), "Count changed a lot: #{item.name}") do
      "<p><strong>#{h(item.name)}</strong> at #{h(movement.location.full_name)}: counted #{movement.counted_quantity}, " \
        "was #{movement.counted_quantity - movement.quantity} (#{h(movement.person&.display_name || "someone")}).</p>"
    end
  end

  # A unit was marked with a condition that needs attention (Needs repair,
  # Broken).
  def needs_repair(unit)
    deliver(self.class.recipients_for(unit.item.team_id, notices: "each"), "Needs repair: #{unit.identifier_name}") do
      "<p><strong>#{h(unit.identifier_name)}</strong> (#{h(unit.item.name)}): #{h(unit.condition_label)}" \
        "#{h(" — #{unit.condition_note}") if unit.condition_note.present?}.</p>"
    end
  end

  # The daily digest for one manager, unless they chose each or off.
  # Without summaries "weekly" gets it daily too. Returns whether it was sent.
  def digest(person, digest)
    return false if digest.empty? || !Inventory::Config.notice_for(person).in?(%w[daily weekly])

    deliver([ person ], "Inventory: #{digest.summary}") { digest_body(digest) } == 1
  end

  # The digest's sections as HTML (names escaped); also the summaries section.
  def digest_body(digest)
    parts = []
    if digest.running_low.any?
      parts << "<h3>Running low</h3><ul>#{digest.running_low.map { |row| "<li>#{h(row.item.name)}: #{row.total} left, order more at #{row.item.reorder_point}</li>" }.join}</ul>" \
        "#{reorder_link}"
    end
    if digest.count_differences.any?
      parts << "<h3>Counts that changed a lot</h3><ul>#{digest.count_differences.map { |movement| "<li>#{h(movement.item.name)} at #{h(movement.location.full_name)}: " \
        "counted #{movement.counted_quantity}, was #{movement.counted_quantity - movement.quantity} (#{h(movement.person&.display_name || "someone")})</li>" }.join}</ul>"
    end
    if digest.needs_repair.any?
      parts << "<h3>Needs repair</h3><ul>#{digest.needs_repair.map { |unit| "<li>#{h(unit.identifier_name)} (#{h(unit.item.name)}): " \
        "#{h(unit.condition_label)}#{h(" — #{unit.condition_note}") if unit.condition_note.present?}</li>" }.join}</ul>"
    end
    parts.join
  end

  private

  def reorder_link
    "<p><a href=\"#{h(Rails.application.routes.url_helpers.inventory_reorder_url)}\">Open the reorder list</a></p>"
  end

  # Sends one email per person with an address and returns how many. The
  # block gives the body.
  def deliver(people, subject)
    return 0 unless Inventory.enabled?

    people = people.compact.uniq.select { |person| person.user&.email.present? }
    return 0 if people.empty?

    gateway = Gateway[:email_sending]
    people.each do |person|
      SendEmailJob.perform_later(gateway, person.user.email, "#{Settings[:title]} - #{subject}", "<p>Hi #{h(person.first_name)},</p>#{yield}")
    end
    people.size
  end
end
