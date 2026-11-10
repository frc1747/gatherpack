# Lets holders of a badge, or members of a team (and the teams below it),
# see a checklist's overall and the listed items for everyone it covers, at
# status or full level (spec §10.2). Only admin-assigned badges can grant,
# so nobody grants themselves access.
class ChecklistGrant < ApplicationRecord
  has_neat_id :chlg
  include CanBeHooked
  has_paper_trail versions: { class_name: "AuditLog" }

  belongs_to :checklist
  belongs_to :badge, optional: true
  belongs_to :team, optional: true
  # Who made it (nil for grants made before this was stored, or once they're
  # deleted), so a kind can check its maker could give it (ItemKind.honours_grant?).
  belongs_to :created_by, class_name: "Person", optional: true

  enum :access, { status: 0, full: 1 }, prefix: :access, validate: true

  validate :one_target
  validate :badge_added_by_admin
  validate :items_on_checklist

  def identifier_name
    "#{checklist&.title}: #{holder_name}"
  end

  def holder_name
    badge ? "#{badge.name} holders" : "#{team&.name} members"
  end

  def items
    checklist.checklist_items.where(id: item_ids)
  end

  # The listed items and every item inside them: what the grant shows.
  def covered_items
    with_children(items.to_a)
  end

  # The covered items whose kind refuses person this grant at its access
  # (ItemKind.grantable_by?). An unregistered kind refuses nothing.
  def refused_items(person)
    covered_items.reject { |item| item.kind_class.nil? || item.kind_class.grantable_by?(item, person, access.to_sym) }
  end

  def item_ids=(ids)
    super(Array(ids).compact_blank)
  end

  private

  def with_children(items)
    items.flat_map { |item| [ item ] + with_children(item.children.to_a) }
  end

  def one_target
    errors.add(:base, "Choose a badge or a team") unless badge_id.present? ^ team_id.present?
  end

  def badge_added_by_admin
    errors.add(:badge, "must be one only admins give") if badge && !badge.added_by_admin?
  end

  def items_on_checklist
    return if checklist.nil? || item_ids.blank?

    errors.add(:item_ids, "must be items on this checklist") if checklist.checklist_items.where(id: item_ids).count != item_ids.uniq.size
  end
end
