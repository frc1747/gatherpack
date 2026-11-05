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

  SHOW_CONTACT_DETAILS_HINT = "People who can see the child also see this person's phone and email. It doesn't let them open the person's profile.".freeze

  # What a guardian can do, listed wherever guardianship is set. A feature that
  # gives guardians more calls RelationshipType.register_guardian_grant("...")
  # inside config.to_prepare, so its line returns after a code reload; a line
  # that's already registered is ignored. Pass if: -> { ... } to list a line only
  # while the condition holds; it's checked each time guardian_grants is read.
  @guardian_grants = { "see the child's profile and fields set to family or guardian levels, and edit them" => nil }

  validate :guardianship_requires_restricted_permission
  validate :show_contact_details_requires_restricted_permission

  def self.guardian_grants
    @guardian_grants.select { |_text, condition| condition.nil? || condition.call }.keys
  end

  def self.register_guardian_grant(text, if: nil)
    @guardian_grants[text] = binding.local_variable_get(:if) unless @guardian_grants.key?(text)
  end

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

  # Whether the saved type is a guardianship, ignoring any unsaved change.
  def guardianship_saved?
    guardianship_was != "none"
  end

  # The question to ask before the saved type changes to or from a guardianship.
  # Nil when no relationships would be affected.
  def guardianship_change_confirmation
    count = relationships.count
    return if count.zero?

    relationship_count = "#{count} #{"relationship".pluralize(count)}"
    guardians = count == 1 ? "a guardian" : "guardians"
    if guardianship_saved?
      "This stops the parent side of #{relationship_count} being #{guardians}."
    else
      "This makes the parent side of #{relationship_count} #{guardians}."
    end
  end

  # The question to ask before the saved type starts showing contact details.
  # The permission check only covers relationships added from now on, so ones
  # added while more people could add this type start showing details too. Nil
  # when it already shows them, or when no relationships would be affected.
  def contact_details_change_confirmation
    return if show_contact_details_was

    count = relationships.count
    return if count.zero?

    "This shows the phone and email of the parent side of #{count} #{"relationship".pluralize(count)} to anyone who can see the child. " \
      "Check them first if members could ever add this type."
  end

  private

  # A guardianship type grants access to the child side's data, so members
  # must not be able to create one about someone else on their own.
  def guardianship_requires_restricted_permission
    if guardianship_minor? && !(added_by_admin? || added_by_manager?)
      errors.add(:guardianship, "can only be set on types added by admins or managers")
    end
  end

  # Contact details bypass the phone and email read levels, so nobody may add
  # themselves as someone's child to get them. A consented type is added by its
  # child side, whatever its permission says. Relationships that already exist
  # aren't covered; see contact_details_change_confirmation.
  def show_contact_details_requires_restricted_permission
    if show_contact_details? && (guardianship_consented? || !(added_by_admin? || added_by_manager?))
      errors.add(:show_contact_details, "can only be set on types that only admins or managers can add")
    end
  end
end
