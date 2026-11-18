# Person fields' columns for the person merge registry. Guarded, so this
# branch runs without feature/person-merge. to_prepare runs after every
# initializer, so the registry is loaded by then whatever the file order.
Rails.application.config.to_prepare do
  next unless defined?(GatherPack::PersonMerge)

  # Both people answered the same field: the kept person's answer stays,
  # unless it's blank, and then the answer of the person merged away fills it.
  GatherPack::PersonMerge.register :person_field_values, :person_id, unique_by: :person_field_id,
    model: PersonFieldValue, label: "Field answers",
    on_conflict: ->(removed, kept) {
      if kept["value"].blank? && removed["value"].present?
        PersonFieldValue.where(id: kept["id"]).update_all(value: removed["value"], updated_at: Time.current)
      end
    }
  GatherPack::PersonMerge.register :person_field_values, :updated_by_id, label: "Field answers changed by"
end
