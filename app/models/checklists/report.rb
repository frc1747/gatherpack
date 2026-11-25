module Checklists
  # The report page's rows and columns for one viewer (spec §10.4): one row
  # per person the viewer may see, columns for the overall and each
  # top-level item the viewer sees for anyone. The viewer's own row and
  # their wards' come first as "Your family" when they see more than that.
  # team_id and status narrow the rows shown (the page's filter bar): status
  # is an overall status, or NOT_COMPLETE for not met or pending. The columns
  # stay those of everyone the viewer sees.
  class Report
    NOT_COMPLETE = "not_complete"
    FILTER_STATUSES = (Checklists::STATUSES + [ NOT_COMPLETE ]).freeze

    attr_reader :checklist, :viewer, :as_of, :status

    def initialize(checklist, viewer, as_of: nil, team_id: nil, status: nil)
      @checklist = checklist
      @viewer = viewer
      @as_of = as_of
      @team_id = team_id
      @status = status
    end

    def statuses
      @statuses ||= Reader.new(checklist, viewer, as_of: as_of).status_for(checklist.reported_person_ids)
    end

    def people
      @people ||= Person.where(id: statuses.keys).index_by(&:id)
    end

    # The checklist's team and the teams below it that hold someone in the
    # report, for the team filter.
    def teams
      @teams ||= Team.where(id: Checklists.team_subtree_ids(checklist.team_id))
        .where(id: Membership.where(person_id: statuses.keys).select(:team_id)).order(:name).to_a
    end

    # The team picked in the filter, when it's one of teams.
    def team
      @team ||= teams.find { |team| team.id == @team_id } if @team_id
    end

    # The rows in the picked team (and the teams below it), any status.
    def in_team
      @in_team ||= if team
        ids = Membership.where(team_id: Checklists.team_subtree_ids(team.id), person_id: statuses.keys).distinct.pluck(:person_id).to_set
        statuses.values.select { |row| ids.include?(row.person_id) }
      else
        statuses.values
      end
    end

    # The rows shown: in the picked team, with the picked overall status.
    def shown
      @shown ||= begin
        wanted = status == NOT_COMPLETE ? %w[not_met pending] : [ status ]
        in_team.select { |row| people[row.person_id] && (status.nil? || wanted.include?(row.overall&.status)) }
      end
    end

    def columns
      @columns ||= begin
        seen = statuses.values.flat_map { |status| status.items.map { |entry| entry.item.id } }.to_set
        Reader.new(checklist, viewer).items.select { |item| seen.include?(item.id) }
      end
    end

    # Whether the overall gets a column: when the viewer sees it for anyone,
    # like an item's column.
    def overall?
      @overall = statuses.values.any?(&:overall) if @overall.nil?
      @overall
    end

    # The table index of the first item column, after Name (and Overall).
    def first_item_index
      overall? ? 2 : 1
    end

    # [[column index, key, label]] for the number filters: the overall's
    # items to do, then each column's measures. Owner-only measures are left
    # out, since most rows wouldn't carry them.
    def measure_filters
      filters = overall? ? [ [ 1, "unmet", "Overall: items to do" ] ] : []
      columns.each_with_index do |item, index|
        Array(item.kind_class&.measures).reject(&:owner_only).each do |measure|
          filters << [ index + first_item_index, measure.key.to_s, "#{item.label}: #{measure.label}" ]
        end
      end
      filters
    end

    def family_ids
      @family_ids ||= ([ viewer.id ] + viewer.wards.ids) & statuses.keys
    end

    # [[heading, statuses]]: "Your family" and "Everyone" when the viewer
    # sees others too, else one unheaded section.
    def sections
      everyone = sorted(shown)
      family = everyone.select { |status| family_ids.include?(status.person_id) }
      others = everyone - family
      return [ [ nil, everyone ] ] if family.empty? || others.empty?

      [ [ "Your family", family ], [ "Everyone", others ] ]
    end

    # How many people in the picked team have each overall status.
    def counts
      in_team.filter_map(&:overall).group_by(&:status).transform_values(&:size)
    end

    # Whether the viewer may excuse this person (a manager or admin, never
    # for themselves or a relative), without a query per person.
    def excusable?(person_id)
      @manager = checklist.manager?(viewer) if @manager.nil?
      return false unless @manager && person_id != viewer.id

      @relative_ids ||= (Relationship.where(parent_id: viewer.id).pluck(:child_id) + Relationship.where(child_id: viewer.id).pluck(:parent_id)).to_set
      !@relative_ids.include?(person_id)
    end

    def name(person_id)
      people[person_id]&.display_name
    end

    private

    # Not complete first, then by the number of unmet items, then name.
    def sorted(list)
      order = { "not_met" => 0, "pending" => 1, "met" => 2, "exempt" => 3 }
      list.sort_by do |status|
        [ order.fetch(status.overall&.status, 4), -status.overall&.measures.to_h["unmet"].to_i, name(status.person_id).to_s ]
      end
    end
  end
end
