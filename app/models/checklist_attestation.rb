# A recorded "this is done" for one person (spec §6.7): "Physical on file",
# "Handbook read". Read by the attested kind through its key. Who may
# attest is the item's setting; see may_attest?.
class ChecklistAttestation < ApplicationRecord
  has_neat_id :chla
  include CanBeHooked
  has_paper_trail versions: { class_name: "AuditLog" }

  belongs_to :person
  belongs_to :attested_by, class_name: "Person", optional: true

  validates :key, presence: true
  validates :statement, presence: true
  validates :attested_at, presence: true
  validates :attested_by, presence: true, on: :create

  before_validation { self.attested_at ||= Time.current }

  def identifier_name
    "#{person&.display_name}: #{statement}"
  end

  # Whether by may attest an attested item for person: the person
  # themselves ("person"); a guardian or the person ("guardian"); or a
  # manager who manages them, never for themselves or a relative
  # ("manager"). Admins may always, except for themselves under "manager".
  def self.may_attest?(item, by, person)
    return false if by.nil? || person.nil?

    case item.config["attested_by"]
    when "manager"
      by.id != person.id && !Checklists.related?(by, person) && (by.admin? || by.can_manage(person))
    when "guardian"
      by.id == person.id || by.admin? || person.guardians.where(id: by.id).exists?
    else
      by.id == person.id || by.admin?
    end
  end
end
