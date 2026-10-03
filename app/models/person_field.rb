class PersonField < ApplicationRecord
  has_neat_id :pfd
  include CanBeHooked
  has_paper_trail versions: { class_name: "AuditLog" }
  belongs_to :team, optional: true
  belongs_to :person_field_group, optional: true
  has_many :person_field_values, dependent: :destroy
  has_many :person_field_badge_grants, dependent: :destroy, inverse_of: :person_field
  accepts_nested_attributes_for :person_field_badge_grants, allow_destroy: true

  # Each level is a fixed set of audience components, relative to the person
  # the value is about. Admins can always see and edit everything.
  PERMISSION_LEVELS = {
    "admin" => [],
    "self" => %i[ subject ],
    "leaders" => %i[ leaders ],
    "self_and_leaders" => %i[ subject leaders ],
    "guardians" => %i[ guardian leaders ],
    "family" => %i[ subject guardian leaders ],
    "team" => %i[ subject guardian leaders teammates ],
    "everyone" => %i[ everyone ]
  }.freeze

  # Explicit integers, so reordering the levels never remaps stored values.
  LEVEL_VALUES = { admin: 0, self: 1, leaders: 2, self_and_leaders: 3, guardians: 4, family: 5, team: 6, everyone: 7 }.freeze

  PHONE_FORMAT = /\A\+?[\d\s().\-]{7,20}(\s*(x|ext\.?)\s*\d{1,6})?\z/i
  KEY_FORMAT = /\A[a-z][a-z0-9_]*\z/
  SYSTEM_READ_ONLY_SOURCES = %w[ user.email ].freeze

  enum :data_type, { string: 0, text: 1, boolean: 2, date: 3, integer: 4, select: 5, multi_select: 6, phone: 7, email: 8 }, prefix: :type, validate: true
  enum :read_permission, LEVEL_VALUES, prefix: :read, validate: true
  enum :write_permission, LEVEL_VALUES, prefix: :write, validate: true

  store_accessor :options, :choices, :choices_setting, :min, :max, :pattern, :pattern_hint

  validates :name, presence: true
  validates :key, presence: true, uniqueness: true, format: { with: KEY_FORMAT, message: "must start with a letter and use only lowercase letters, numbers, and underscores" }
  validate :key_unchanged, on: :update
  validate :data_type_unchanged_once_used, on: :update
  validate :system_attributes_unchanged, on: :update
  validate :write_within_read
  validate :options_make_sense

  before_validation :generate_key, on: :create
  before_validation :drop_unused_options
  before_destroy :ensure_destroyable, prepend: true

  scope :active, -> { where(archived_at: nil) }
  scope :archived, -> { where.not(archived_at: nil) }
  scope :system, -> { where.not(system_source: nil) }
  scope :custom, -> { where(system_source: nil) }
  scope :applicable_to, ->(person) { where(team_id: nil).or(where(team_id: person.all_ancestor_teams.select(:id))) }
  scope :ordered, -> { left_joins(:person_field_group).order(Arel.sql("person_field_groups.position ASC NULLS FIRST"), "person_field_groups.name", :position, :name) }

  # Fields that take part in profiles and forms. The feature flag governs
  # custom fields only; system fields are always enforced.
  def self.in_use
    GatherPack::Features.enabled?(:person_fields) ? active : active.system
  end

  def self.ransackable_attributes(auth_object = nil)
    [ "name", "key", "updated_at" ]
  end

  def identifier_name
    name
  end

  def identifier_icon
    "clipboard-list"
  end

  def readable_by?(viewer, subject)
    PersonFieldAccess.new(viewer, subject).readable?(self)
  end

  def writable_by?(viewer, subject)
    PersonFieldAccess.new(viewer, subject).writable?(self)
  end

  def access_for(viewer, subject, mode)
    PersonFieldAccess.new(viewer, subject).access(self, mode)
  end

  def applies_to?(person)
    team_id.nil? || person.all_ancestor_teams.where(id: team_id).exists?
  end

  # Everyone the field applies to: members of its team or any team below it.
  def applicable_people
    team ? team.descendant_people : Person.all
  end

  # The people whose value for this field the viewer may see (or edit), as
  # one relation. Must agree with PersonFieldAccess for every subject.
  def readable_subjects_for(viewer)
    subjects_for(viewer, :read)
  end

  def writable_subjects_for(viewer)
    subjects_for(viewer, :write)
  end

  def restricted?
    !read_everyone?
  end

  AUDIENCE_ROLES = { subject: :subject, guardians: :guardian, leaders: :leaders, teammates: :teammates, everyone: :everyone }.freeze

  # Each audience's access to this field for one subject (:none, :read or
  # :write), plus badge grants. Guardians are left out until a relationship
  # type grants guardianship, so organizations without them never see the
  # term.
  def audience_for(subject)
    audience = AUDIENCE_ROLES.to_h { |role, component| [ role, role_access(component) ] }
    audience.delete(:guardians) unless RelationshipType.guardianship_configured?
    audience[:subject] = :read if audience[:subject] == :write && system_read_only?
    audience[:badges] = person_field_badge_grants.to_h { |grant| [ grant.badge, grant.write? && !system_read_only? ? :write : :read ] }
    audience[:guardianship_ends_on] = subject.guardianship_ends_on if audience.fetch(:guardians, :none) != :none
    audience
  end

  def archived?
    archived_at.present?
  end

  def system?
    system_source.present?
  end

  def system_read_only?
    SYSTEM_READ_ONLY_SOURCES.include?(system_source)
  end

  def archive!
    update!(archived_at: Time.current)
  end

  def restore!
    update!(archived_at: nil)
  end

  def destroyable?
    archived? && !system?
  end

  def choice_list
    if choices_setting.present?
      Settings[choices_setting.to_sym].to_s.split(",").map(&:strip).reject(&:blank?)
    else
      Array(choices)
    end
  end

  def choices_text
    Array(choices).join("\n")
  end

  def choices_text=(text)
    self.choices = text.to_s.lines.map(&:strip).reject(&:blank?)
  end

  # Stored value (JSON text) -> Ruby value.
  def cast(raw)
    return (type_boolean? ? false : nil) if raw.nil?

    value = JSON.parse(raw)
    case data_type
    when "boolean" then value == true
    when "date" then Date.iso8601(value.to_s)
    when "integer" then Integer(value)
    when "multi_select" then Array(value)
    else value.to_s
    end
  rescue JSON::ParserError, ArgumentError, TypeError
    nil
  end

  # Ruby value -> stored value (JSON text). nil means "no value".
  def serialize(value)
    return nil if value.nil?
    (value.is_a?(Date) ? value.iso8601 : value).to_json
  end

  # Form input -> [value, error]. A blank input normalizes to nil, which
  # clears the value. `current` keeps a retired choice selectable for the
  # person who already has it.
  def normalize(input, current: nil)
    case data_type
    when "boolean"
      [ ActiveModel::Type::Boolean.new.cast(input) ? true : nil, nil ]
    when "multi_select"
      values = Array(input).map { |value| value.to_s.strip }.reject(&:blank?).uniq
      return [ nil, nil ] if values.empty?
      (values - choice_list - Array(current)).any? ? [ nil, "includes a choice that isn't available" ] : [ values, nil ]
    else
      text = input.to_s.strip
      text.empty? ? [ nil, nil ] : normalize_text(text, current)
    end
  end

  # Values for system fields live in their own columns.
  def system_value(person)
    system_source == "user.email" ? person.user&.email : person[system_source]
  end

  private

  def role_access(component)
    reaches = ->(level) { PERMISSION_LEVELS.fetch(level).include?(component) || level == "everyone" }
    if reaches.call(write_permission) && !system_read_only?
      :write
    elsif reaches.call(read_permission)
      :read
    else
      :none
    end
  end

  def normalize_text(text, current)
    case data_type
    when "string"
      matches_pattern?(text) ? [ text, nil ] : [ nil, pattern_hint.presence || "isn't in the expected format" ]
    when "text"
      [ text, nil ]
    when "date"
      date = parse_date(text)
      return [ nil, "isn't a valid date" ] unless date
      out_of_range?(date, parse_date(min), parse_date(max)) ? [ nil, range_message(min, max) ] : [ date, nil ]
    when "integer"
      number = parse_integer(text)
      return [ nil, "must be a whole number" ] unless number
      out_of_range?(number, parse_integer(min), parse_integer(max)) ? [ nil, range_message(min, max) ] : [ number, nil ]
    when "select"
      choice_list.include?(text) || text == current ? [ text, nil ] : [ nil, "isn't one of the choices" ]
    when "phone"
      PHONE_FORMAT.match?(text) ? [ text, nil ] : [ nil, "isn't a valid phone number" ]
    when "email"
      URI::MailTo::EMAIL_REGEXP.match?(text) ? [ text, nil ] : [ nil, "isn't a valid email address" ]
    end
  end

  def matches_pattern?(text)
    pattern.blank? || Regexp.new(pattern, timeout: 0.5).match?(text)
  rescue RegexpError, Regexp::TimeoutError
    false
  end

  def parse_date(value)
    Date.iso8601(value.to_s) if value.present?
  rescue Date::Error
    nil
  end

  def parse_integer(value)
    Integer(value.to_s, 10) if value.present?
  rescue ArgumentError
    nil
  end

  def out_of_range?(value, low, high)
    (low && value < low) || (high && value > high)
  end

  def range_message(low, high)
    if low.present? && high.present?
      "must be between #{low} and #{high}"
    elsif low.present?
      "must be #{low} or more"
    else
      "must be #{high} or less"
    end
  end

  def subjects_for(viewer, mode)
    return Person.none if viewer.nil? || (mode == :write && system_read_only?)
    return applicable_people if viewer.admin?

    level = mode == :read ? read_permission : write_permission
    relations = PERMISSION_LEVELS.fetch(level).map { |component| component_people(component, viewer) }
    viewer_badge_ids = viewer.badge_ids
    person_field_badge_grants.each do |grant|
      relations << grant.covered_people if (mode == :read || grant.write?) && viewer_badge_ids.include?(grant.badge_id)
    end
    return Person.none if relations.empty?

    relations.map { |relation| Person.where(id: relation.select(:id)) }.reduce(:or)
      .where(id: applicable_people.select(:id))
  end

  def component_people(component, viewer)
    case component
    when :subject then Person.where(id: viewer.id)
    when :guardian then viewer.wards
    when :leaders then viewer.all_managed_people
    when :teammates then Person.joins(:memberships).where(memberships: { team_id: viewer.teams.select(:id) })
    when :everyone then Person.all
    end
  end

  def generate_key
    return if key.present? || name.blank?

    base = name.parameterize(separator: "_").sub(/\A[^a-z]+/, "").presence || "field"
    candidate = base
    suffix = 1
    candidate = "#{base}_#{suffix += 1}" while PersonField.exists?(key: candidate)
    self.key = candidate
  end

  def drop_unused_options
    allowed = case data_type
    when "select", "multi_select" then %w[ choices choices_setting ]
    when "integer", "date" then %w[ min max ]
    when "string" then %w[ pattern pattern_hint ]
    else []
    end
    self.options = (options || {}).slice(*allowed).reject { |_, value| value.blank? }
  end

  def key_unchanged
    errors.add(:key, "can't be changed once created") if will_save_change_to_key?
  end

  def data_type_unchanged_once_used
    if will_save_change_to_data_type? && person_field_values.exists?
      errors.add(:data_type, "can't be changed once values exist. Archive this field and create a new one instead")
    end
  end

  def system_attributes_unchanged
    return unless system?

    %i[ data_type options team_id system_source ].each do |attribute|
      errors.add(attribute, "can't be changed on a system field") if will_save_change_to_attribute?(attribute)
    end
    errors.add(:write_permission, "is managed by account settings") if system_read_only? && !write_admin?
  end

  # As with Page, editing can't reach further than viewing.
  def write_within_read
    read = PERMISSION_LEVELS[read_permission]
    write = PERMISSION_LEVELS[write_permission]
    return if read.nil? || write.nil? || read.include?(:everyone)

    errors.add(:write_permission, "can't include people who can't see this field") unless (write - read).empty?
  end

  def options_make_sense
    case data_type
    when "select", "multi_select"
      if choices_setting.blank?
        errors.add(:choices, "can't be blank") if Array(choices).empty?
        errors.add(:choices, "can't contain duplicates") if Array(choices).uniq.size != Array(choices).size
      end
    when "integer"
      validate_range(parse_integer(min), parse_integer(max), "a whole number")
    when "date"
      validate_range(parse_date(min), parse_date(max), "a date (YYYY-MM-DD)")
    when "string"
      begin
        Regexp.new(pattern) if pattern.present?
      rescue RegexpError => e
        errors.add(:pattern, "isn't a valid regular expression (#{e.message})")
      end
    end
  end

  def validate_range(low, high, kind)
    errors.add(:min, "must be #{kind}") if min.present? && low.nil?
    errors.add(:max, "must be #{kind}") if max.present? && high.nil?
    errors.add(:max, "must be at least the minimum") if low && high && high < low
  end

  def ensure_destroyable
    return if destroyable?

    errors.add(:base, system? ? "System fields can't be deleted" : "Archive this field before deleting it")
    throw :abort
  end
end
