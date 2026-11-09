module ChecklistsHelper
  STATUS_CLASSES = { "met" => "text-bg-success", "pending" => "text-bg-warning", "not_met" => "text-bg-danger", "exempt" => "text-bg-secondary" }.freeze

  # A status pill for an ItemStatus (its label or word).
  def checklist_status_badge(entry)
    tag.span(entry.text, class: "badge #{STATUS_CLASSES.fetch(entry.status, "text-bg-light")}")
  end

  # How far along a count item is, for its bar; nil for an item without a count.
  def checklist_item_percent(entry)
    measures = entry.measures || {}
    return unless measures["confirmed"] && measures["owed"].to_f.positive?

    [ (measures["confirmed"].to_f * 100 / measures["owed"].to_f).floor, 100 ].min
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
  # leader can do). A fix may carry a requirement, { "record" => a global
  # id, "query" => a policy question such as "update?" }: the link shows
  # only when the viewer's policy answers yes, else the label as text.
  def checklist_fix(checklist, entry, person_id)
    fix = entry.fix
    return if fix.blank? || entry.met? || entry.exempt?
    return tag.span(fix["label"], class: "text-body-secondary") unless checklist_fix_allowed?(fix["requires"])

    if fix["action"] == "attest"
      # A group ("any of") shows its child's fix, with that child's item_id.
      item = (fix["item_id"] && checklist.checklist_items.find_by(id: fix["item_id"])) || entry.item
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

  def checklist_fix_allowed?(requires)
    return true if requires.blank?

    query = requires["query"].to_s
    return false unless query.match?(/\A[a-z_]+\?\z/)

    record = GlobalID::Locator.locate(requires["record"].to_s)
    return false if record.nil?

    record_policy = policy(record)
    record_policy.respond_to?(query) && record_policy.public_send(query)
  rescue ActiveRecord::RecordNotFound, URI::InvalidURIError, Pundit::NotDefinedError
    false
  end

  # The kinds the current person may set up on this checklist
  # (ItemKind.authorable_by? on a new item of each kind, built outside the
  # checklist's loaded items so the page doesn't list it).
  def checklist_kind_options(checklist)
    person = current_user&.person
    Checklists.item_kinds.filter_map do |key, kind|
      next if person.nil? || !kind.authorable_by?(ChecklistItem.new(checklist: checklist, kind: key), person)

      [ kind.label, key, kind.description ]
    end
  end
end
