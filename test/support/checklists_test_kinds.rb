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

  # A kind like a private field: a person's result shows only to them and
  # to admins, and only admins may set it up. Not met, with the "value" in
  # its summary.
  class Private < Checklists::ItemKind
    def self.visible_to?(_item, viewer, person)
      viewer.admin? || viewer.id == person.id
    end

    def self.authorable_by?(_item, author)
      author.admin?
    end

    def evaluate(person_ids)
      person_ids.index_with { Checklists::Result.not_met("Private value") }
    end
  end

  # A kind that pools people like a count item: seen at the "group" level,
  # and a person reaches the results of anyone related to them by any
  # relationship, guardian or not. Always not met.
  class Pooled < Checklists::ItemKind
    def self.default_read_level(_item) = "group"

    def self.group_reach(_item, viewer, person_ids)
      related = Relationship.where(parent_id: viewer.id, child_id: person_ids).pluck(:child_id) +
        Relationship.where(child_id: viewer.id, parent_id: person_ids).pluck(:parent_id)
      ([ viewer.id ] & person_ids) + related
    end

    def evaluate(person_ids)
      person_ids.index_with { Checklists::Result.not_met("1 of 2 shifts") }
    end
  end
end
