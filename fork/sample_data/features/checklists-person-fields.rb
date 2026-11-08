# (feature/checklists-person-fields).
#
# Two profile-field items on the core's "Trip Eligibility" checklist, using
# the Photo Release and Emergency Contact fields person-fields creates:
#
# - "Photo release" (is yes): Chloe and Grace are done, Kate's release is
#   set to no, everyone else is blank and so Not yet.
# - "Emergency contact" (is filled in, changed since the season began):
#   Chloe's is current, Grace's was last changed before the season started
#   (Not yet, "Not changed since ..."), the rest are blank.
Hbr::SampleData.feature "feature/checklists-person-fields" do |s|
  s.enable_feature :checklists
  s.enable_feature :person_fields
  checklist = Checklist.find_by!(title: "Trip Eligibility")
  season_start, = s.clock.season
  photo = PersonField.find_by!(key: "photo_release")
  contact = PersonField.find_by!(key: "emergency_contact")

  item = lambda do |label, position, config|
    record = ChecklistItem.find_or_initialize_by(checklist: checklist, label: label)
    record.assign_attributes(kind: "person_field", position: position)
    record.config_params = config
    record.save! if record.new_record? || record.changed?
    record
  end
  item.call("Photo release", 6, { field_id: photo.id, operator: "yes" })
  item.call("Emergency contact", 7, { field_id: contact.id, operator: "filled_in", changed_since: { mode: "date", date: season_start.iso8601 } })

  # Fills a blank field; a value another feature's sample data already set
  # (person-fields gives Grace a contact) is kept. A given date is applied
  # either way, so "changed since" sees the field as last changed then.
  fill = lambda do |first, field, value, changed_at = nil|
    person = s.person(first)
    person.set_field_value(field, value) unless PersonFieldValue.exists?(person: person, person_field: field)
    PersonFieldValue.where(person: person, person_field: field).update_all(updated_at: changed_at) if changed_at
  end
  fill.call("Chloe", photo, true)
  fill.call("Grace", photo, true)
  fill.call("Kate", photo, false)
  fill.call("Chloe", contact, "Dana Reyes, 555-0142", s.clock.days_ago(5))
  fill.call("Grace", contact, "Paula Miller, 555-0187", season_start - 30)

  Checklists::Refresher.new(checklist.reload, silent: true).call
  results = ->(label, first) { checklist.checklist_results.find_by(item: checklist.checklist_items.find_by!(label: label), person: s.person(first)) }
  s.expect("Chloe's photo release is met") { results.call("Photo release", "Chloe")&.met? }
  s.expect("Kate's photo release is not met") { results.call("Photo release", "Kate")&.not_met? }
  s.expect("Grace's emergency contact is out of date") { results.call("Emergency contact", "Grace")&.not_met? }
end
