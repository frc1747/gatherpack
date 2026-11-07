module Checklists
  # For the sign-up sheet panel: the checklists the sheet's positions need
  # that the viewer, or someone they can sign up, hasn't finished. Each
  # entry has the checklist, the names of the positions needing it, and
  # [person, status, covered] for the people who don't pass: status is the
  # Checklists::Status the viewer may see (nil when they see none), covered
  # whether the checklist covers the person at all.
  class SignupSheetNeeds
    Entry = Struct.new(:checklist, :position_names, :people, keyword_init: true)

    def initialize(signup_sheet, viewer)
      @signup_sheet = signup_sheet
      @viewer = viewer
    end

    def entries
      return [] if @viewer.nil? || !Checklists.enabled?

      rules = SignupPositionRule.checklist.where(signup_position_id: @signup_sheet.signup_positions.select(:id))
        .where.not(checklist_id: nil).includes(:checklist, :signup_position).to_a
      return [] if rules.empty?

      takers = @signup_sheet.takers_for(@viewer).to_a
      rules.group_by(&:checklist).filter_map do |checklist, checklist_rules|
        failing = takers.select { |taker| checklist_rules.any? { |rule| rule.check(taker, nil) } }
        next if failing.empty?

        statuses = Checklists.status_for(checklist, failing, viewer: @viewer)
        Entry.new(checklist: checklist, position_names: checklist_rules.map { |rule| rule.signup_position.name }.uniq,
          people: failing.map { |person| [ person, statuses[person.id], !checklist_rules.first.checklist_status(person).nil? ] })
      end
    end
  end
end
