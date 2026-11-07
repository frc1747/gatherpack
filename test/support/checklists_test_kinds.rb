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
end
