module PersonFieldsHelper
  DATA_TYPE_LABELS = {
    "string" => "Short text", "text" => "Long text", "boolean" => "Yes/No", "date" => "Date", "integer" => "Number",
    "select" => "Choice", "multi_select" => "Multiple choice", "phone" => "Phone", "email" => "Email"
  }.freeze

  def person_field_type_label(field)
    DATA_TYPE_LABELS.fetch(field.data_type)
  end

  # Level choices for the field form. Without any guardianship types, the
  # guardians-only level is hidden and the rest avoid mentioning guardians.
  def person_field_level_options(guardianship = RelationshipType.guardianship_configured?)
    levels = AudienceLevels::LEVEL_VALUES.keys.map(&:to_s)
    levels -= [ "guardians" ] unless guardianship
    levels.map { |level| [ person_field_level_label(level, guardianship), level ] }
  end

  def person_field_level_label(level, guardianship = RelationshipType.guardianship_configured?)
    key = guardianship ? "label" : "label_without_guardians"
    t("person_fields.levels.#{level}.#{key}", default: t("person_fields.levels.#{level}.label"))
  end

  def person_field_level_description(level, guardianship = RelationshipType.guardianship_configured?)
    key = guardianship ? "description" : "description_without_guardians"
    types = RelationshipType.where.not(guardianship: :none).order(:parent_label).map(&:parent_label).to_sentence
    t("person_fields.levels.#{level}.#{key}", default: t("person_fields.levels.#{level}.description", guardian_types: types), guardian_types: types)
  end

  def person_field_level_descriptions
    guardianship = RelationshipType.guardianship_configured?
    AudienceLevels::LEVEL_VALUES.keys.map(&:to_s).index_with { |level| person_field_level_description(level, guardianship) }
  end

  # The confirmation for "Apply recommended privacy settings", listing every
  # change. People who can see these details today may lose access.
  def recommended_privacy_confirmation(changes)
    lines = changes.map do |field, attributes|
      parts = attributes.map do |attribute, (from, to)|
        label = attribute == :read_permission ? "who can see" : "who can edit"
        "#{label}: #{person_field_level_label(from).downcase_first} → #{person_field_level_label(to).downcase_first}"
      end
      "• #{field.name}: #{parts.join("; ")}"
    end
    "Apply recommended privacy settings?\n\n#{lines.join("\n")}\n\nPeople who can see these details today may no longer be able to."
  end

  # A value formatted for the profile and roster.
  def person_field_display(field, value)
    return "—" if value.nil? || value == [] || value == ""

    case field.data_type
    when "boolean" then value ? "Yes" : "No"
    when "date" then nice_date(value)
    when "multi_select" then Array(value).join(", ")
    when "email" then mail_to(value)
    when "phone" then link_to(value, "tel:#{value.gsub(/[^\d+]/, "")}")
    when "text" then simple_format(value, {}, wrapper_tag: "span")
    else value.to_s
    end
  end

  # Value for a field's input, or for read-only text on the edit form.
  def person_field_current_value(person, field, rows)
    return person.field_value(field) if field.system?
    field.cast(rows[field.id]&.value)
  end

  # A simple_form input for one writable field. Inputs post under
  # person[person_field_values][key]; errors come from person.errors[key].
  def person_field_input(form, field, value)
    name = "person[person_field_values][#{field.key}]"
    options = { label: field.name, hint: field.help_text.presence, required: field.required?, input_html: { name: name, id: "person_field_#{field.key}" } }

    case field.data_type
    when "string", "phone", "email"
      options[:as] = { "string" => :string, "phone" => :tel, "email" => :email }.fetch(field.data_type)
      options[:input_html][:value] = value
    when "text"
      options[:as] = :text
      options[:input_html].merge!(value: value, rows: 3)
    when "integer"
      options[:as] = :integer
      options[:input_html][:value] = value
    when "date"
      options[:as] = :string
      options[:input_html].merge!(type: :date, value: value.respond_to?(:iso8601) ? value.iso8601 : value)
    when "boolean"
      options[:as] = :boolean
      options[:input_html][:checked] = ActiveModel::Type::Boolean.new.cast(value) == true
    when "select"
      options.merge!(as: :select, collection: person_field_choices(field, value), selected: value, include_blank: true)
    when "multi_select"
      options.merge!(as: :check_boxes, collection: person_field_choices(field, value), checked: Array(value))
      options[:input_html][:name] = "#{name}[]"
      options[:input_html].delete(:id)
      return hidden_field_tag("#{name}[]", "", id: nil) + form.input(field.key.to_sym, **options)
    end

    form.input field.key.to_sym, **options
  end

  # The field's choices, plus retired ones the person still has.
  def person_field_choices(field, value)
    retired = Array(value).compact_blank - field.choice_list
    field.choice_list.map { |choice| [ choice, choice ] } + retired.map { |choice| [ "#{choice} (retired)", choice ] }
  end

  # One or two short sentences, relative to the viewer, about who else can
  # see and change this field for this subject. Only call this for fields the
  # viewer can read.
  def access_notes(field, subject, viewer)
    return [] unless field.restricted? || field.person_field_badge_grants.any?

    audience = field.audience_for(subject)
    name = subject.display_name.presence || subject.first_name
    scope = "person_fields.access_notes"
    notes = []

    if viewer.admin?
      notes << person_field_summary(field, audience, name)
      return notes
    end

    if subject.guardians.where(id: viewer.id).exists?
      notes << t("#{scope}.guardian.subject_#{audience[:subject]}", name: name)
      ends_on = audience[:guardianship_ends_on]
      if field.restricted? && ends_on && ends_on <= 90.days.from_now.to_date
        notes << t("#{scope}.guardian.ends_on", name: name, date: nice_date(ends_on))
      end
    elsif viewer.id == subject.id
      notes << t("#{scope}.subject.guardians_#{audience[:guardians]}") if %i[ read write ].include?(audience[:guardians])
      notes << t("#{scope}.subject.leaders_only_write") if audience[:subject] == :read && audience[:leaders] == :write && field.restricted?
    elsif viewer.can_manage(subject)
      notes << t("#{scope}.leader.guardians_none", name: name) if audience[:guardians] == :none
      notes << t("#{scope}.leader.subject_none", name: name) if audience[:subject] == :none
    end

    notes << t("#{scope}.badges", badges: audience[:badges].keys.map(&:name).to_sentence) if audience[:badges].any?
    notes
  end

  def person_field_summary(field, audience, name)
    scope = "person_fields.access_notes.summary_parts"
    parts = %i[ subject guardians leaders teammates ].select { |role| audience.fetch(role, :none) != :none }
      .map { |role| t("#{scope}.#{role}", name: name) }
    parts += audience[:badges].keys.map(&:name)
    parts = [ t("#{scope}.admins") ] if parts.empty?
    t("person_fields.access_notes.summary", audiences: parts.join(", "))
  end

  # Explains an access reason from PersonFieldAccess#access, for Preview as….
  def person_field_access_reason(reason, field, viewer, subject)
    case reason
    when :admin then "Site admin"
    when :subject then "Their own profile"
    when :guardian
      types = Relationship.active_guardianships.where(parent_id: viewer.id, child_id: subject.id).map { |relationship| relationship.relationship_type.parent_label }
      "Guardian (#{types.uniq.to_sentence})"
    when :leaders
      teams = Team.where(id: viewer.memberships.where(manager: true).select(:team_id)).where(id: subject.all_ancestor_teams.select(:id)).order(:name).pluck(:name)
      "Leader of #{teams.to_sentence}"
    when :teammates
      "Shares #{(viewer.teams & subject.teams).map(&:name).sort.to_sentence}"
    when :everyone then "Visible to anyone who can see the profile"
    when Badge then "Holds the #{reason.name} badge"
    else
      field.read_admin? ? "Admins only" : "Not in the field's audience"
    end
  end

  def person_field_read_only_note(field)
    return t("person_fields.access_notes.managed_by_account") if field.system_read_only?
    level = field.write_admin? ? "admins" : person_field_level_label(field.write_permission).downcase_first
    t("person_fields.access_notes.read_only", level: level)
  end

  def person_field_lock_title(field, subject)
    person_field_summary(field, field.audience_for(subject), subject.display_name.presence || subject.first_name)
  end
end
