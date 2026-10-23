class PersonFieldGroup < ApplicationRecord
  has_neat_id :pfgr
  has_paper_trail versions: { class_name: "AuditLog" }
  has_many :person_fields, dependent: :nullify

  validates :name, presence: true

  scope :ordered, -> { order(:position, :name) }

  def self.ransackable_attributes(auth_object = nil)
    [ "name", "position", "updated_at" ]
  end

  # Swaps this section with its neighbour.
  def move(direction)
    groups = PersonFieldGroup.ordered.to_a
    index = groups.index(self)
    other = direction.to_s == "up" ? index - 1 : index + 1
    return if other.negative? || other >= groups.size

    groups[index], groups[other] = groups[other], groups[index]
    transaction do
      groups.each_with_index { |group, position| group.update!(position: position) if group.position != position }
    end
  end

  def identifier_name
    name
  end

  def identifier_icon
    "layer-group"
  end
end
