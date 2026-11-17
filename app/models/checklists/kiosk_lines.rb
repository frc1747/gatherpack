# The labels the time kiosk lists for a person who scanned: their items that
# aren't done, from checklists with an item an organizer marked show_on_kiosk.
# Only those checklists are evaluated, and none when nothing is marked.
module Checklists::KioskLines
  def self.for(person)
    ids = ChecklistItem.where(show_on_kiosk: true).distinct.pluck(:checklist_id)
    return [] if ids.empty?

    covering = ChecklistResult.where(person_id: person.id, item_id: nil).select(:checklist_id)
    Checklist.where(id: ids).where(id: covering).where.not(status: :archived).order(:title).flat_map do |checklist|
      next [] if checklist.draft? && !checklist.organizer?(person)

      status = Checklists.status_for(checklist, [ person ], viewer: person)[person.id]
      next [] unless status

      status.items.select { |entry| entry.item.show_on_kiosk? && (entry.not_met? || entry.pending?) }.map { |entry| entry.item.label }
    end.uniq
  end
end
