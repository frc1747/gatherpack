# The inventory managers' daily digest (inventory spec §3.12), scheduled in
# config/recurring.d/inventory.yml. Each manager gets one email covering
# the teams whose inventory they manage, and nothing when inventory is off
# or nothing changed for them.
class InventoryDigestJob < ApplicationJob
  queue_as :default

  def perform(since = nil)
    return unless Inventory.enabled?
    # The summaries feature sends it instead (daily email or Weekly Infodump).
    return if defined?(GatherPack::Digests) && GatherPack::Digests.handles?(:inventory)

    since = since ? Time.zone.parse(since.to_s) : 1.day.ago
    digest = Inventory::Digest.new(since: since)
    return if digest.empty?

    notices = InventoryNotices.new
    InventoryNotices.managers.each do |person, team_ids|
      notices.digest(person, digest.for_teams(team_ids))
    end
  end
end
