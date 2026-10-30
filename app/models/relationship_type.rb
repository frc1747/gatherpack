class RelationshipType < ApplicationRecord
  has_neat_id :rety
  include CanBeHooked
  has_paper_trail versions: { class_name: "AuditLog" }
  has_many :relationships
  enum :permission, added_by_admin: 0, added_by_manager: 1, added_by_team_member: 2, added_by_participant: 3, added_by_user: 4
  enum :guardianship, { none: 0, minor: 1, consented: 2 }, prefix: true

  GUARDIANSHIP_LABELS = {
    "none" => "None",
    "minor" => "Guardian while the child is a minor",
    "consented" => "Guardian with the child's consent"
  }.freeze

  validate :guardianship_requires_restricted_permission
  validate :guardianship_not_widened_while_linked

  def self.guardianship_configured?
    where.not(guardianship: :none).exists?
  end

  def self.ransackable_attributes(auth_object = nil)
    [ "parent_label", "child_label", "updated_at", "permission" ]
  end

  def identifier_name
    "#{parent_label} - #{child_label}"
  end

  def guardianship?
    !guardianship_none?
  end

  # Existing links were made under the type's current setting, so widening
  # it would hand them guardianship nobody agreed to.
  def guardianship_locked?
    persisted? && relationships.exists?
  end

  private

  # A guardianship type grants access to the child side's data, so members
  # must not be able to create one about someone else on their own.
  def guardianship_requires_restricted_permission
    if guardianship_minor? && !(added_by_admin? || added_by_manager?)
      errors.add(:guardianship, "can only be set on types added by admins or managers")
    end
  end

  def guardianship_not_widened_while_linked
    return unless will_save_change_to_guardianship? && guardianship_locked?

    # none < minor < consented: each grants guardianship in more cases.
    if self.class.guardianships.fetch(guardianship) > self.class.guardianships.fetch(guardianship_in_database)
      errors.add(:guardianship, "can't grant more while this type already has links. To give guardianship, create a new type and link people to it")
    end
  end
end
