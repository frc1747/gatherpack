# Emails to inventory managers (inventory spec §3.12), sent like the other
# GatherPack notices: one SendEmailJob per recipient through the email
# gateway, so no one sees anyone else's address, and nothing is sent (but
# nothing fails) when no gateway is set up. Nothing is sent while inventory
# is turned off. Members get no notices.
#
# Recipients for an item are the inventory managers within reach of its
# team: holders of an inventory_managers grant reaching it, and the
# managers of the team or a team above it. Admins aren't added for being
# admins.
class InventoryNotices
  include ERB::Util

  # The people who hear about a team's items.
  def self.recipients_for(team_id)
    managers.select { |person, team_ids| team_ids.include?(team_id) }.keys
  end

  # { person => Set of team ids whose inventory notices they get }.
  def self.managers
    reach = Inventory::Config.managers
    people = reach.holders.to_a | Person.joins(:memberships).where(memberships: { manager: true }).distinct.to_a
    people.to_h do |person|
      managed = Membership.where(person_id: person.id, manager: true).pluck(:team_id)
      managed += Team.where(id: managed).flat_map(&:all_descendant_ids)
      [ person, (managed + reach.granted_team_ids(person)).to_set ]
    end
  end

  # An item went onto the reorder list (inventory_reorder_notice "each").
  def running_low(item)
    total = item.total_stock
    deliver(self.class.recipients_for(item.team_id), "Running low: #{item.name}") do
      "<p><strong>#{h(item.name)}</strong> is running low: #{h(item.stock_unit.quantity_text(total))} left, " \
        "order more at #{item.reorder_point}.</p>#{reorder_link}"
    end
  end

  # The daily digest for one manager. Returns whether it was sent.
  def digest(person, digest)
    return false if digest.empty?

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
