module ChecklistsHelper
  STATUS_CLASSES = { "met" => "text-bg-success", "pending" => "text-bg-warning", "not_met" => "text-bg-danger", "exempt" => "text-bg-secondary" }.freeze

  # A status pill for an ItemStatus (its label or word).
  def checklist_status_badge(entry)
    tag.span(entry.text, class: "badge #{STATUS_CLASSES.fetch(entry.status, "text-bg-light")}")
  end

  def checklist_status_class(status)
    STATUS_CLASSES.fetch(status.to_s, "text-bg-light")
  end

  def checklist_window_text(record)
    start = if record.starts_within_amount.present?
      "within the last #{pluralize(record.starts_within_amount, record.starts_within_unit.to_s.singularize)}"
    elsif record.starts_on
      "from #{l(record.starts_on, format: :long)}"
    end
    finish = record.ends_on ? "to #{l(record.ends_on, format: :long)}" : "up to now"
    [ start, finish ].compact.join(" ").upcase_first
  end

  # The fix as a link, a confirm button, or plain text (something only a
  # leader can do).
  def checklist_fix(checklist, entry, person_id)
    fix = entry.fix
    return if fix.blank? || entry.met? || entry.exempt?

    if fix["action"] == "attest"
      item = entry.item
      attestation = ChecklistAttestation.new(person_id: person_id)
      attestation.item = item
      return tag.span(fix["label"] == "I confirm" ? "Not confirmed yet" : fix["label"], class: "text-body-secondary") unless policy(attestation).create?

      label = entry.acts_for == :guardian ? "Confirm for #{Person.find(person_id).first_name}" : (entry.acts_for == :self ? "I confirm" : "Confirm")
      button_to label, checklist_checklist_attestations_path(checklist, item_id: item.id, person_id: person_id),
        class: "btn btn-sm btn-outline-success", form_class: "d-inline"
    elsif fix["path"].present? && fix["path"].start_with?("/")
      link_to fix["label"], fix["path"], class: "btn btn-sm btn-outline-primary"
    else
      tag.span(fix["label"], class: "text-body-secondary")
    end
  end

  def checklist_kind_options
    Checklists.item_kinds.map { |key, kind| [ kind.label, key, kind.description ] }
  end
end
