# The checklist results shown next to applications, for a page of them at
# once: one Checklists.status_for call per checklist, whatever the number of
# rows, and only what the viewer may see (Checklists::Visibility).
class Intake::ApplicationChecklists
  def initialize(applications, viewer)
    @applications = Array(applications)
    @viewer = viewer
    @statuses = Hash.new { |hash, id| hash[id] = {} }
    @asked = Hash.new { |hash, id| hash[id] = Set.new }
    ActiveRecord::Associations::Preloader.new(records: @applications, associations: { registration: :checklist }).call
    @by_id = @applications.index_by(&:id)
  end

  # The applicant's Checklists::Status on the application's registration's
  # checklist, or nil (no checklist, features off, not covered or not
  # visible to the viewer).
  def status_for(application)
    # The page's own copy of the row, whose registration is preloaded.
    application = @by_id.fetch(application.id, application)
    checklist = application.registration&.active_checklist
    return if checklist.nil? || @viewer.nil?

    load(checklist, people_for(checklist)) if @asked[checklist.id].empty?
    load(checklist, [ application.person_id ]) unless @asked[checklist.id].include?(application.person_id)
    @statuses[checklist.id][application.person_id]
  end

  # "4 of 6 complete": the counting items that apply to them.
  def self.counts_text(status)
    counting = status.items.select { |entry| entry.item.counts? && !entry.exempt? }
    "#{counting.count(&:met?)} of #{counting.size} complete"
  end

  # Labels of the counting items still not done for the person, as they see
  # them, for the "You're in. Next: ..." notice.
  def self.still_to_do(application)
    checklist = application.registration&.active_checklist
    return [] unless checklist

    status = Checklists.status_for(checklist, [ application.person ], viewer: application.person)[application.person_id]
    return [] unless status

    status.explained.select { |entry| entry.item.counts? && (entry.not_met? || entry.pending?) }.map { |entry| entry.item.label }
  end

  private

  def people_for(checklist)
    @applications.select { |application| application.registration&.checklist_id == checklist.id }.map(&:person_id).uniq
  end

  # Remembers who was asked, so people the viewer can't see aren't looked
  # up again.
  def load(checklist, person_ids)
    @statuses[checklist.id].merge!(Checklists.status_for(checklist, person_ids, viewer: @viewer))
    @asked[checklist.id].merge(person_ids)
  end
end
