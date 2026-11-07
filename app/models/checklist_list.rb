# "Record this list" (spec §9.4): a read-only snapshot of a checklist's
# names, statuses and configuration at one moment, for a decision such as
# a trip roster. Results keep changing; the list doesn't.
class ChecklistList < ApplicationRecord
  has_neat_id :chll
  include CanBeHooked
  has_paper_trail versions: { class_name: "AuditLog" }

  belongs_to :checklist
  belongs_to :recorded_by, class_name: "Person", optional: true

  validates :recorded_at, presence: true
  validates :recorded_by, presence: true, on: :create

  def identifier_name
    "#{checklist&.title}: #{I18n.l(recorded_at.to_date, format: :long)}"
  end

  # Snapshots everyone the checklist covers, as its organizers see them.
  def self.record!(checklist, by:, note: nil)
    statuses = Checklists.status_for(checklist, checklist.people_covered.ids, viewer: by)
    people = Person.where(id: statuses.keys).index_by(&:id)
    rows = statuses.values.sort_by { |status| people[status.person_id].display_name.to_s }.map do |status|
      {
        "person_id" => status.person_id, "name" => people[status.person_id].display_name,
        "overall" => status.overall&.status, "overall_text" => status.overall&.text,
        "items" => status.all_items.to_h { |entry| [ entry.item.id, { "status" => entry.status, "text" => entry.text, "summary" => entry.summary } ] }
      }
    end
    configuration = {
      "title" => checklist.title, "team" => checklist.team.name, "window" => checklist.window.to_s,
      "cutoff_on" => checklist.cutoff_on&.iso8601,
      "items" => checklist.checklist_items.order(:position).map do |item|
        { "id" => item.id, "parent_id" => item.parent_id, "label" => item.label, "kind" => item.kind, "describe" => item.describe, "counts" => item.counts }
      end
    }
    create!(checklist: checklist, recorded_by: by, note: note, recorded_at: Time.current, rows: rows, configuration: configuration)
  end

  # The rows as this viewer may read them: cells an item's kind hides from
  # them (Checklists.visible_person_ids, groups included) are dropped, and a
  # row's overall is worked out again from the counting items they may see
  # when one is hidden. Cells of items since removed show only to admins.
  def rows_for(viewer)
    current = checklist.checklist_items.includes(children: :children).index_by(&:id)
    person_ids = rows.map { |row| row["person_id"] }
    allowed = Array(configuration["items"]).to_h do |entry|
      item = current[entry["id"]]
      ids = if item then Checklists.visible_person_ids(item, viewer, person_ids)
      elsif viewer&.admin? then person_ids
      else []
      end
      [ entry["id"], ids.to_set ]
    end
    counting = Array(configuration["items"]).select { |entry| entry["counts"] && entry["parent_id"].nil? }

    rows.map do |row|
      items = row["items"].to_h.select { |item_id, _| allowed[item_id]&.include?(row["person_id"]) }
      row = row.merge("items" => items)
      next row if counting.all? { |entry| allowed[entry["id"]]&.include?(row["person_id"]) }

      shown = counting.select { |entry| allowed[entry["id"]]&.include?(row["person_id"]) }
      next row.merge("overall" => nil, "overall_text" => nil) if shown.empty?

      statuses = shown.filter_map { |entry| items.dig(entry["id"], "status") }.reject { |status| status == "exempt" }
      overall = if statuses.include?("not_met") then "not_met"
      elsif statuses.include?("pending") then "pending"
      else "met"
      end
      row.merge("overall" => overall, "overall_text" => checklist.word_for(overall))
    end
  end
end
