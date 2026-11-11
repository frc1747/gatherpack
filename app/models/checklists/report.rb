module Checklists
  # The report page's rows and columns for one viewer (spec §10.4): one row
  # per person the viewer may see, columns for the overall and each
  # top-level item the viewer sees for anyone. The viewer's own row and
  # their wards' come first as "Your family" when they see more than that.
  class Report
    attr_reader :checklist, :viewer, :as_of

    def initialize(checklist, viewer, as_of: nil)
      @checklist = checklist
      @viewer = viewer
      @as_of = as_of
    end

    def statuses
      @statuses ||= Reader.new(checklist, viewer, as_of: as_of).status_for(checklist.reported_person_ids)
    end

    def people
      @people ||= Person.where(id: statuses.keys).index_by(&:id)
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
      everyone = sorted(statuses.values)
      family = everyone.select { |status| family_ids.include?(status.person_id) }
      others = everyone - family
      return [ [ nil, everyone ] ] if family.empty? || others.empty?

      [ [ "Your family", family ], [ "Everyone", others ] ]
    end

    def counts
      statuses.values.filter_map(&:overall).group_by(&:status).transform_values(&:size)
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
