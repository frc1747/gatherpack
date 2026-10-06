class Hook < ApplicationRecord
  has_neat_id :hook
  has_paper_trail versions: { class_name: "AuditLog" }

  validates :name, presence: true

  def self.catalog
    targets = [ "announcements", "badges", "badge_assignments", "events", "checkins", "memberships", "people", "relationships", "relationship_types", "person_fields", "person_field_values", "person_field_badge_grants", "forms", "form_responses", "form_submissions", "form_signatures", "form_badge_grants", "form_audience_rules", "teams", "users", "pages", "tokens", "ledgers", "ledger_entries", "ledger_ownerships", "ledger_taggings", "ledger_tags" ].map do |k|
      [ "create", "update", "destroy" ].map { |e| [ k, e ].join(" - ") }
    end.flatten

    targets << "token - activate"
    targets << "person_fields - value changed"
    targets << "form_submissions - submitted"
    targets << "form_submissions - activated"
    targets << "form_responses - completed"
    targets << "form_responses - incomplete"

    targets.sort
  end

  def self.ransackable_attributes(auth_object = nil)
    %w[ name event updated_at ]
  end

  def identifier_icon
    "timeline"
  end

  def run(model)
    eval(code, binding, name, 0)
  end
end
