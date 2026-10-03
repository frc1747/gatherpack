class Person < ApplicationRecord
  has_neat_id :per
  include CanBeHooked

  has_paper_trail versions: { class_name: "AuditLog" }
  belongs_to :user, optional: true
  has_many :memberships, dependent: :destroy
  has_many :membership_applications, dependent: :destroy
  has_many :teams, through: :memberships
  has_many :badge_assignments, dependent: :destroy
  has_many :badges, through: :badge_assignments
  has_many :checkins, dependent: :destroy
  has_many :events, through: :checkins
  has_many :tokens, as: :tokenable
  has_many :ledger_ownerships, dependent: :destroy, as: :owner
  has_many :time_clock_punches, dependent: :destroy
  has_many :calendar_notes, as: :noteable
  has_many :person_field_values, dependent: :destroy, autosave: true
  before_save :check_display_name
  validate :person_field_errors
  after_save :run_person_field_hooks
  accepts_nested_attributes_for :user
  has_one_attached :avatar
  attr_accessor :email

  def self.ransackable_attributes(auth_object = nil)
    [ "address", "birthday", "created_at", "dietary_restrictions", "display_name", "first_name", "gender", "id", "last_name", "phone_number", "shirt_size", "updated_at", "user_id" ]
  end

  def self.ransackable_associations(auth_object = nil)
    [ "user", "tokens" ]
  end

  def admin?
    user&.admin
  end

  def architect?
    user&.architect
  end

  def manager?
    user&.admin || memberships.where(manager: true).any?
  end

  def roles
    roles = []
    roles << "admin" if user&.admin
    roles << "architect" if user&.architect
    roles << "manager" if memberships.where(manager: true).any?
    roles
  end

  def managed_teams
    user&.admin? ? Team.all : Team.joins(:memberships).where(memberships: { person_id: id, manager: true })
  end

  def managed_people
    user&.admin ? Person.all : Person.joins(:memberships).where(memberships: { team_id: managed_teams.select(:id) }).distinct
  end

  def can_manage(person)
    return true if user&.admin?
    return false if person.nil?
    all_managed_people.where(id: person.id).exists?
  end

  def all_teams
    Team.where(id: all_team_ids)
  end

  def all_team_ids
    direct_team_ids = teams.select(:id)
    managed_team_ids = memberships.where(manager: true).select(:team_id)
    descendant_ids = Team.where(id: managed_team_ids).flat_map(&:all_descendants).map(&:id)
    ancestor_ids = Team.where(id: direct_team_ids).flat_map(&:all_ancestors).map(&:id)
    direct_team_ids + descendant_ids + ancestor_ids
  end

  def all_ancestor_teams
    Team.where(id: all_ancestor_team_ids)
  end

  def all_ancestor_team_ids
    direct_team_ids = teams.select(:id)
    ancestor_ids = Team.where(id: direct_team_ids).flat_map(&:all_ancestors).map(&:id)
    direct_team_ids + ancestor_ids
  end

  def all_managed_teams
    return Team.all if user&.admin?
    managed_team_ids = memberships.where(manager: true).pluck(:team_id)
    descendant_ids = Team.where(id: managed_team_ids).flat_map(&:all_descendant_ids)
    Team.where(id: managed_team_ids + descendant_ids)
  end

  def all_managed_people
    Person.joins(:memberships)
      .where(memberships: { team_id: all_managed_teams.select(:id) })
      .distinct
  end

  def relationships
    Relationship.where(parent_id: id).or(Relationship.where(child_id: id))
  end

  # People who are currently guardians of this person.
  def guardians
    Person.where(id: Relationship.active_guardianships.where(child_id: id).select(:parent_id))
  end

  # People this person is currently a guardian of.
  def wards
    Person.where(id: Relationship.active_guardianships.where(parent_id: id).select(:child_id))
  end

  # The date minor guardianships of this person end, when an age limit is set.
  def guardianship_ends_on
    limit = Relationship.guardianship_age_limit
    birthday + limit.years if limit && birthday
  end

  def guardianship_expired?
    limit = Relationship.guardianship_age_limit
    return false unless limit
    birthday ? birthday <= Date.current - limit.years : Relationship.guardianship_ends_without_birthday?
  end

  def relatives(relationship_type = nil)
    r = relationships
    r = r.where(relationship_type: relationship_type) if relationship_type
    relative_ids = r.pluck(:parent_id, :child_id).flatten.uniq - [ id ]
    Person.where(id: relative_ids)
  end

  def distant_relatives(relationship_type = nil)
    visited = Set.new([ id ])
    to_visit = relatives.to_a
    matching_relatives = []

    while to_visit.any?
      person = to_visit.pop
      next if visited.include?(person.id)
      visited << person.id
      if relationship_type
        rels = Relationship.where(
          "(parent_id = :a AND child_id = :b) OR (parent_id = :b AND child_id = :a)",
          a: person.id, b: id
        ).where(relationship_type: relationship_type)
        matching_relatives << person if rels.exists?
      else
        matching_relatives << person
      end
      to_visit.concat(person.relatives(nil).reject { |r| visited.include?(r.id) })
    end

    matching_relatives.uniq
  end

  # Person fields this viewer may see or edit on this person's record.
  def readable_fields_for(viewer)
    access = PersonFieldAccess.new(viewer, self)
    person_fields_for_access.select { |field| access.readable?(field) }
  end

  def writable_fields_for(viewer)
    access = PersonFieldAccess.new(viewer, self)
    person_fields_for_access.select { |field| access.writable?(field) }
  end

  # Existing value rows for these fields, plus unsaved rows for the rest.
  def field_values_for(fields)
    fields.map do |field|
      person_field_values.detect { |row| row.person_field_id == field.id } ||
        PersonFieldValue.new(person: self, person_field: field)
    end
  end

  # Trusted accessors for Hooks, Reports, jobs, and the console: no viewer
  # check. Use readable_fields_for / assign_field_values for user requests.
  def field_value(key)
    field = key.is_a?(PersonField) ? key : PersonField.find_by!(key: key.to_s)
    return field.system_value(self) if field.system?
    field.cast(person_field_values.detect { |row| row.person_field_id == field.id }&.value)
  end

  def set_field_value(key, value)
    field = key.is_a?(PersonField) ? key : PersonField.find_by!(key: key.to_s)
    raise ArgumentError, "#{field.key} is managed by account settings" if field.system_read_only?
    return update!(field.system_source => value) if field.system?

    row = person_field_values.find_or_initialize_by(person_field: field)
    if value.nil? || value == [] || value == ""
      row.destroy! if row.persisted?
      person_field_values.reset
    else
      row.update!(value: field.serialize(value))
    end
  end

  # Applies person field input from a form on behalf of `acting`. Keys the
  # actor can't write are ignored. Values are saved, and the "person_fields -
  # value changed" hooks run, when the person is saved.
  def assign_field_values(values, acting:)
    access = PersonFieldAccess.new(acting, self)
    fields = person_fields_for_access.index_by(&:key)
    @person_field_input_errors = []
    @person_field_changes = []

    values.to_h.each do |key, input|
      field = fields[key.to_s]
      next unless field && access.writable?(field)

      current = field_value(field)
      value, error = field.normalize(input, current: current)
      next @person_field_input_errors << [ field.key, error ] if error

      new_value = field.cast(field.serialize(value))
      next if new_value == current

      stage_field_value(field, value, acting)
      @person_field_changes << PersonFieldChange.new(person: self, field: field, old_value: current, new_value: new_value, changed_by: acting)
    end

    fields.each_value do |field|
      next unless field.required? && access.writable?(field)
      value = field_value_after_staging(field)
      @person_field_input_errors << [ field.key, "can't be blank" ] if value.blank? && value != false
    end
  end

  def ledger_ids
    LedgerOwnership.where(owner: self).pluck(:ledger_id)
  end

  def ledgers
    Ledger.where(id: ledger_ids)
  end

  def current_time_clock_periods
    all_current_time_clock_periods = TimeClockPeriod.where("start_time <= ? AND end_time >= ?", Time.now, Time.now)
    all_current_time_clock_periods.where(team_id: all_team_ids)
      .or(all_current_time_clock_periods.where(team_id: nil))
  end

  def identifier_name
    display_name.presence || id
  end

  def identifier_icon
    "user"
  end

  def avatar_512
    avatar.variant(resize_to_fill: [ 512, 512 ], format: :jpg) if avatar.attached?
  end

  def avatar_64
    avatar.variant(resize_to_fill: [ 64, 64 ], format: :jpg) if avatar.attached?
  end

  private

  def person_fields_for_access
    PersonField.in_use.applicable_to(self).ordered.includes(:person_field_group, person_field_badge_grants: :badge).to_a
  end

  def stage_field_value(field, value, acting)
    return self[field.system_source] = value if field.system?

    row = person_field_values.detect { |existing| existing.person_field_id == field.id }
    if value.nil?
      return unless row
      row.persisted? ? row.mark_for_destruction : person_field_values.delete(row)
    else
      row ||= person_field_values.build(person_field: field)
      row.value = field.serialize(value)
      row.updated_by = acting
      row.acting = acting
    end
  end

  def field_value_after_staging(field)
    return field.system_value(self) if field.system?
    row = person_field_values.detect { |existing| existing.person_field_id == field.id }
    row.nil? || row.marked_for_destruction? ? field.cast(nil) : field.cast(row.value)
  end

  def person_field_errors
    Array(@person_field_input_errors).each { |key, message| errors.add(key.to_sym, message) }
  end

  def run_person_field_hooks
    changes = Array(@person_field_changes)
    @person_field_changes = []
    @person_field_input_errors = []
    return if changes.empty?

    hooks = Hook.where(event: "person_fields - value changed").to_a
    changes.each { |change| hooks.each { |hook| hook.run(change) } }
  end

  def check_display_name
    self.display_name = first_name + " " + last_name if display_name.blank? && !first_name.blank? && !last_name.blank?
  end
end
