# Brings the built-in profile data (email, phone, address, birthday, dietary
# restrictions, shirt size, gender) under person field access control. Every
# field starts at today's behaviour, so nothing changes until an admin
# restricts it. Uses its own minimal models so it keeps working as the app's
# models change.
class CreateSystemPersonFields < ActiveRecord::Migration[8.1]
  class Group < ActiveRecord::Base
    self.table_name = "person_field_groups"
  end

  class Field < ActiveRecord::Base
    self.table_name = "person_fields"
  end

  SECTIONS = [ "Contact", "Details" ].freeze
  FIELDS = [
    [ "user.email", "email", "Email", 8, "Contact", 0 ],
    [ "phone_number", "phone", "Phone", 7, "Contact", 3 ],
    [ "address", "address", "Address", 0, "Contact", 3 ],
    [ "birthday", "birthday", "Birthday", 3, "Details", 3 ],
    [ "dietary_restrictions", "dietary_restrictions", "Dietary Restrictions", 0, "Details", 3 ],
    [ "shirt_size", "shirt_size", "Shirt Size", 5, "Details", 3, { "choices_setting" => "shirt_sizes" } ],
    [ "gender", "gender", "Gender", 5, "Details", 3, { "choices_setting" => "gender_options" } ]
  ].freeze
  EVERYONE = 7

  def up
    groups = SECTIONS.to_h do |name|
      group = Group.find_by(name: name) || Group.create!(name: name, position: (Group.maximum(:position) || -1) + 1)
      [ name, group ]
    end

    FIELDS.each_with_index do |(source, key, name, data_type, section, write, options), position|
      next if Field.exists?(system_source: source)

      key = "#{key}_system" if Field.exists?(key: key)
      Field.create!(system_source: source, key: key, name: name, data_type: data_type, options: options || {},
        person_field_group_id: groups.fetch(section).id, position: position,
        read_permission: EVERYONE, write_permission: write, show_on_profile: true, required: false)
    end
  end

  def down
    Field.where.not(system_source: nil).delete_all
  end
end
