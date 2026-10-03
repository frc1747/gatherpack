class PersonFieldGroup < ApplicationRecord
  has_neat_id :pfgr
  has_paper_trail versions: { class_name: "AuditLog" }
  has_many :person_fields, dependent: :nullify

  validates :name, presence: true

  scope :ordered, -> { order(:position, :name) }

  def self.ransackable_attributes(auth_object = nil)
    [ "name", "position", "updated_at" ]
  end

  def identifier_name
    name
  end

  def identifier_icon
    "layer-group"
  end
end
