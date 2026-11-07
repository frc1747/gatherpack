# A recorded "this is done" for one person (spec §6.7): "Physical on file",
# "Handbook read". Read by the attested kind through its key. Who may
# attest is the item's setting; see may_attest?.
class ChecklistAttestation < ApplicationRecord
  has_neat_id :chla
  include CanBeHooked
  has_paper_trail versions: { class_name: "AuditLog" }

  # "Who confirms" levels, least strict first. attested_as is the level a
  # confirmation satisfied when it was made (checked by may_attest?).
  LEVELS = { "person" => 0, "guardian" => 1, "manager" => 2 }.freeze

  belongs_to :person
  belongs_to :attested_by, class_name: "Person", optional: true

  # The attested item it's made through, for the permission check; not stored.
  attr_accessor :item

  validates :key, presence: true
  validates :statement, presence: true
  validates :attested_at, presence: true
  validates :attested_by, presence: true, on: :create
  validates :attested_as, inclusion: { in: LEVELS.keys }, allow_nil: true

  before_validation { self.attested_at ||= Time.current }

  def identifier_name
    "#{person&.display_name}: #{statement}"
  end

  # Of these attestations (for one key), the ones this item accepts: made by
  # someone its "who confirms" setting allows for that person. A
  # confirmation made through another item with the same key counts only
  # when it would have been allowed here too. Batch: a few queries per
  # distinct attester, whatever the number of people.
  #
  # A confirmation recorded as satisfying a level at least as strict as the
  # item's counts as made, whatever its maker's roles are now; older ones
  # without a recorded level are checked against the maker's roles today.
  def self.accepted_by(item, attestations)
    return [] if attestations.empty?

    who = item.config["attested_by"]
    needed = LEVELS.fetch(who.to_s, 0)
    recorded, unrecorded = attestations.partition { |attestation| attestation.attested_as && LEVELS[attestation.attested_as].to_i >= needed }
    recorded + current_roles_accept(who, unrecorded)
  end

  def self.current_roles_accept(who, attestations)
    return [] if attestations.empty?

    attester_ids = attestations.map(&:attested_by_id).compact.uniq
    person_ids = attestations.map(&:person_id).uniq
    admin_ids = Person.joins(:user).where(id: attester_ids, users: { admin: true }).ids.to_set

    case who
    when "manager"
      related = Relationship.where(parent_id: attester_ids, child_id: person_ids).pluck(:parent_id, :child_id)
      related += Relationship.where(child_id: attester_ids, parent_id: person_ids).pluck(:child_id, :parent_id)
      related = related.to_set
      managed = (attester_ids - admin_ids.to_a).index_with do |attester_id|
        teams = Checklists.team_subtree_ids(Membership.where(person_id: attester_id, manager: true).pluck(:team_id))
        Membership.where(team_id: teams, person_id: person_ids).distinct.pluck(:person_id).to_set
      end
      attestations.select do |attestation|
        by = attestation.attested_by_id
        by && by != attestation.person_id && !related.include?([ by, attestation.person_id ]) &&
          (admin_ids.include?(by) || managed[by]&.include?(attestation.person_id))
      end
    when "guardian"
      guardians = Relationship.active_guardianships.where(parent_id: attester_ids, child_id: person_ids).pluck(:parent_id, :child_id).to_set
      attestations.select do |attestation|
        by = attestation.attested_by_id
        by == attestation.person_id || admin_ids.include?(by) || guardians.include?([ by, attestation.person_id ])
      end
    else
      attestations.select { |attestation| attestation.attested_by_id == attestation.person_id || admin_ids.include?(attestation.attested_by_id) }
    end
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
