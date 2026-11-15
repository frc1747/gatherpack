module Checklists
  module Kinds
    # A member of any of the chosen teams or a team below one, optionally
    # only memberships made within the item's dates.
    class TeamMember < ItemKind
      class << self
        def label = "Team member"
        def description = "Is on a team"
        def uses_dates? = true

        def settings
          [
            ItemKind::Setting.new(key: :team_ids, type: :teams, label: "Teams", hint: "Any of these, or a team below one"),
            ItemKind::Setting.new(key: :within_dates, type: :boolean, label: "Only if they joined within the item's dates")
          ]
        end

        def references = { "team_ids" => "Team" }

        def invalidations
          [ [ ::Membership, ->(membership) { [ membership.person_id ] } ], [ ::Team, ->(_team) { :all } ] ]
        end

        def problems(item)
          problems = missing_references(item)
          problems << "No team chosen" if Array(item.config["team_ids"]).compact_blank.empty?
          problems
        end

        def validate(item)
          item.errors.add(:base, "Choose at least one team") if Array(item.config["team_ids"]).compact_blank.empty?
        end

        def describe(item)
          names = referenced_records(item, "team_ids").map(&:name)
          "On #{names.size > 1 ? "any of: " : ""}#{names.to_sentence(two_words_connector: ", ", last_word_connector: ", ")} (or a team below)"
        end
      end

      def evaluate(person_ids)
        teams = self.class.referenced_records(item, "team_ids")
        memberships = ::Membership.where(person_id: person_ids, team_id: Checklists.team_subtree_ids(teams.map(&:id)), created_at: ..window.end_time)
        memberships = memberships.where(created_at: window.start_time..window.end_time) if config["within_dates"]
        team_names = ::Team.where(id: memberships.select(:team_id)).pluck(:id, :name).to_h
        on = memberships.pluck(:person_id, :team_id).group_by(&:first)
        wanted = teams.map(&:name).to_sentence(two_words_connector: " or ", last_word_connector: " or ")

        person_ids.index_with do |person_id|
          names = Array(on[person_id]).map { |_, team_id| team_names[team_id] }.uniq
          if names.any?
            Result.met("On #{names.to_sentence}")
          else
            Result.not_met("Not on #{wanted.presence || "the team"}", fix: { "label" => "Ask a leader", "by" => "leader" })
          end
        end
      end
    end
  end
end
