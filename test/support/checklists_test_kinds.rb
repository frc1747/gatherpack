# Item kinds that exist only in tests, for the extension points connectors
# use. Register them in a test's setup and unregister them in teardown.
module ChecklistsTestKinds
  # A kind with a relative date setting: met when the person was made on
  # or after it.
  class JoinedSince < Checklists::ItemKind
    def self.settings
      [ Checklists::ItemKind::Setting.new(key: :since, type: :relative_date, label: "Since") ]
    end

    def evaluate(person_ids)
      since = relative_date(:since)&.resolve(context.as_of)
      created = Person.where(id: person_ids).pluck(:id, :created_at).to_h
      person_ids.index_with do |id|
        since.nil? || created[id].to_date >= since ? Checklists::Result.met("Joined") : Checklists::Result.not_met("Joined earlier")
      end
    end
  end

  # A kind with a form section of its own: a table of named rows with a
  # share each. Met when it has at least one row.
  class Rows < Checklists::ItemKind
    VIEWS = Rails.root.join("test/fixtures/files/checklist_views").to_s

    def self.form_partial = "checklist_items/test_rows"
    def self.form_params = [ { rows: %i[name share] } ]

    def self.normalize_form(params)
      rows = params["rows"]
      rows = rows.values if rows.is_a?(Hash)
      { "rows" => Array(rows).map { |row| row.to_h.stringify_keys }.select { |row| row["name"].present? }
        .map { |row| { "name" => row["name"].strip, "share" => row["share"].to_i } } }
    end

    def self.validate(item)
      item.errors.add(:base, "Add at least one row") if Array(item.config["rows"]).empty?
    end

    def evaluate(person_ids)
      person_ids.index_with { Checklists::Result.met("#{config["rows"].size} rows") }
    end
  end
end
