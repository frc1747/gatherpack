# Custom fields at several read levels, a badge grant, guardianship with two
# parents, and a member login. Values are filled for some people and left
# empty for others.
Hbr::SampleData.people "Paula Miller", "Owen Walker"

Hbr::SampleData.feature "feature/person-fields" do |s|
  s.enable_feature :person_fields
  PersonField.ensure_system_fields!
  admin = s.login(:admin)

  # Guardianship ends at 18, so Olive's ends within a month.
  s.setting :guardianship_age_limit, 18
  parent_type = s.upsert!(RelationshipType, { parent_label: "Parent", child_label: "Child" },
    permission: "added_by_manager", guardianship: "minor")

  { "Grace" => 16, "Kate" => 14 }.each do |first, age|
    s.person(first).update!(birthday: s.clock.date(-100) << (12 * age))
  end
  s.person("Olive").update!(birthday: s.clock.date(21) << (12 * 18))

  guardian = lambda do |parent, child|
    next if Relationship.exists?(parent: parent, child: child, relationship_type: parent_type)

    Relationship.create!(parent: parent, child: child, relationship_type: parent_type, created_by: admin)
  end
  paula = s.login!(:parent1, "parent1", "Paula", "Miller")
  owen = s.login!(:parent2, "parent2", "Owen", "Walker")
  guardian.call(paula, s.person("Grace"))
  guardian.call(paula, s.person("Kate"))
  guardian.call(owen, s.person("Olive"))

  s.login!(:member, "member", "Ella", "Brown")

  health = PersonFieldGroup.find_or_create_by!(name: "Health") { |group| group.position = (PersonFieldGroup.maximum(:position) || -1) + 1 }
  contact = PersonFieldGroup.find_or_create_by!(name: "Contact")
  field = lambda do |key, name, data_type, group, read, write, help|
    s.upsert!(PersonField, { key: key }, name: name, data_type: data_type, person_field_group: group,
      read_permission: read, write_permission: write, help_text: help)
  end
  medical = field.call("medical_notes", "Medical Notes", "text", health, "family", "guardians",
    "Conditions, medication, anything a leader should know.")
  field.call("emergency_contact", "Emergency Contact", "string", contact, "self_and_leaders", "self_and_leaders",
    "Name and phone number.")
  field.call("allergies", "Allergies", "string", health, "everyone", "family", nil)
  field.call("photo_release", "Photo Release", "boolean", health, "family", "guardians",
    "Photos of this person may be shared publicly.")

  # Health Officer: an adult volunteer who can read medical notes for everyone.
  health_officer = s.upsert!(Badge, { name: "Health Officer" },
    badge_type: BadgeType.find_by!(name: "Certification"), team: nil, permission: "added_by_admin", color: "#c01c28", short: "notes-medical")
  BadgeAssignment.find_or_create_by!(badge: health_officer, person: s.person("Isla"))
  PersonFieldBadgeGrant.find_or_create_by!(person_field: medical, badge: health_officer) { |grant| grant.access = "read" }

  {
    "Grace" => { "medical_notes" => "Carries an inhaler.", "allergies" => "Peanuts", "photo_release" => true,
                 "emergency_contact" => "Paula Miller, 555-0101" },
    "Kate" => { "allergies" => "None", "photo_release" => false, "emergency_contact" => "Paula Miller, 555-0101" },
    "Olive" => { "medical_notes" => "Seasonal asthma.", "emergency_contact" => "Owen Walker, 555-0102" },
    "Ella" => { "allergies" => "Shellfish", "emergency_contact" => "Sam Brown, 555-0103" },
    "Ben" => { "allergies" => "None" }
  }.each do |first, values|
    person = s.person(first)
    values.each { |key, value| person.set_field_value(key, value) }
  end

  s.report "4 custom fields, Health Officer grant (Isla), guardians Paula (Grace, Kate) and Owen (Olive), logins parent1@ parent2@ member@"
  s.expect("Paula is Grace's guardian") { s.person("Grace").guardians.include?(paula) }
  s.expect("Olive is still a minor") { s.person("Olive").guardians.include?(owen) }
end
