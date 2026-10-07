class Relationship < ApplicationRecord
  has_neat_id :rel
  include CanBeHooked
  has_paper_trail versions: { class_name: "AuditLog" }
  belongs_to :relationship_type
  belongs_to :parent, class_name: :Person
  belongs_to :child, class_name: :Person

  validate :no_self_relationships
  validate :permission_check

  attr_accessor :start_node, :node_occupant, :node_occupant_id, :other_occupant, :other_occupant_id, :created_by

  # Relationships whose parent side is currently a guardian of the child side:
  # every consented guardianship, plus minor guardianships whose child hasn't
  # reached the age limit (when one is set).
  scope :active_guardianships, -> {
    guardianships = joins(:relationship_type).where.not(relationship_types: { guardianship: RelationshipType.guardianships[:none] })
    limit = guardianship_age_limit
    if limit
      minors = Person.where("people.birthday > ?", Date.current - limit.years)
      minors = minors.or(Person.where(birthday: nil)) unless guardianship_ends_without_birthday?
      guardianships.where(relationship_types: { guardianship: RelationshipType.guardianships[:consented] })
        .or(guardianships.where(child_id: minors.select(:id)))
    else
      guardianships
    end
  }

  def self.guardianship_age_limit
    limit = Settings[:guardianship_age_limit].to_s.strip
    limit.match?(/\A\d+\z/) && limit.to_i.positive? ? limit.to_i : nil
  end

  def self.guardianship_ends_without_birthday?
    Settings[:guardianship_ends_without_birthday] == true
  end

  def reify
    raise ArgumentError unless start_node.present? && node_occupant.present?

    type_id, side = start_node.split(":")
    self.relationship_type = RelationshipType.find(type_id)

    if side == "p"
      self.parent = node_occupant
      self.child = other_occupant if other_occupant.present?
    elsif side == "c"
      self.child = node_occupant
      self.parent = other_occupant if other_occupant.present?
    else
      raise ArgumentError
    end
  end

  def node_occupant_id=(id)
    self.node_occupant = Person.find(id)
  end

  def other_occupant_id=(id)
    self.other_occupant = Person.find(id)
  end

  def reverse
    self.parent, self.child = self.child, self.parent
  end

  private

  def no_self_relationships
    if parent != nil && parent == child
      errors.add(:parent, "cannot be the same person as the child")
      errors.add(:child, "cannot be the same person as the parent")
    end
  end

  def permission_check
    return consent_check if relationship_type.guardianship_consented?

    errors.tap do |t|
       t.add(:parent, "does not meet relationship requirements")
       t.add(:child, "does not meet relationship requirements")
    end unless case relationship_type.permission
               when "added_by_admin"
      created_by_admin?
               when "added_by_manager"
      created_by_manager? || created_by_admin?
               when "added_by_team_member"
      created_by_team_member? || created_by_manager? || created_by_admin?
               when "added_by_participant"
      created_by_participant? || created_by_manager? || created_by_admin?
               when "added_by_user"
      true
               end
  end

  # Consent can only come from the person whose data it opens up.
  def consent_check
    unless created_by == child || created_by_admin?
      errors.add(:base, "Only #{child&.identifier_name || "the #{relationship_type.child_label.downcase}"} or an admin can add this relationship")
    end
  end

  def created_by_participant?
    created_by == parent || created_by == child
  end

  def created_by_team_member?
    (created_by.teams & parent.teams).present? && (created_by.teams & child.teams).present?
  end

  def created_by_manager?
    (created_by.all_managed_teams & parent.teams).present? && (created_by.all_managed_teams & child.teams).present?
  end

  def created_by_admin?
    created_by.user.admin?
  end
end
