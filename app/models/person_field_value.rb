class PersonFieldValue < ApplicationRecord
  has_neat_id :pfv
  include CanBeHooked
  has_paper_trail versions: { class_name: "AuditLog" }
  belongs_to :person
  belongs_to :person_field
  belongs_to :updated_by, class_name: "Person", optional: true

  # The person making the change, when it comes from a signed-in user.
  # Trusted callers (Hooks, Reports, the console) leave it unset.
  attr_accessor :acting

  validates :person_field_id, uniqueness: { scope: :person_id }
  validate :permission_check, if: -> { acting && (new_record? || will_save_change_to_value?) }

  def cast_value
    person_field.cast(value)
  end

  private

  def permission_check
    errors.add(:value, "can't be changed by you") unless person_field.writable_by?(acting, person)
  end
end
