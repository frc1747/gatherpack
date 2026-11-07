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
      "items" => checklist.checklist_items.order(:position).map { |item| { "id" => item.id, "label" => item.label, "kind" => item.kind, "describe" => item.describe, "counts" => item.counts } }
    }
    create!(checklist: checklist, recorded_by: by, note: note, recorded_at: Time.current, rows: rows, configuration: configuration)
  end
end
