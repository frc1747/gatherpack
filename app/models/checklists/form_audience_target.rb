module Checklists
  # The form audience target "checklist" (spec §10.3): a rule asks the
  # people a checklist covers, or those of them who have or haven't
  # finished it (from stored results). This is how people on no team yet,
  # such as applicants, get a joining checklist's forms. While checklists are
  # turned off the rule asks nobody. Prepended to FormAudienceRule.
  module FormAudienceTarget
    MATCH_WORDS = { "covered" => "everyone %s covers", "met" => "people who have finished %s", "not_met" => "people who haven't finished %s" }.freeze

    def self.prepended(base)
      base.belongs_to :checklist, optional: true
      base.enum :checklist_match, { covered: 0, met: 1, not_met: 2 }, prefix: :checklist, validate: true
      base.validate :checklist_doesnt_read_its_own_form
    end

    def target
      target_checklist? ? checklist : super
    end

    def description
      return super unless target_checklist?

      text = "#{effect.capitalize} #{format(MATCH_WORDS.fetch(checklist_match), checklist&.title || "(deleted)")}"
      text += " (ignored while Checklists are turned off)" unless Checklists.enabled?
      text
    end

    def people
      return super unless target_checklist?
      return Person.none unless checklist && Checklists.enabled?

      covered = Checklists.people_covered_by(checklist)
      case checklist_match
      when "met" then covered.where(id: Checklists.people_meeting(checklist).select(:id))
      when "not_met" then covered.where.not(id: Checklists.people_meeting(checklist).select(:id))
      else covered
      end
    end

    # A checklist reaches its own team and below (applicants reach the team
    # they applied to, which is below it too).
    def within_team?(outer)
      return super unless target_checklist?
      return true if outer.nil?

      checklist.present? && (outer.all_descendant_ids + [ outer.id ]).include?(checklist.team_id)
    end

    private

    def clear_other_targets
      super
      return if target_checklist?

      self.checklist_id = nil
      self.checklist_match = :covered
    end

    # Asking only people who have (or haven't) finished a checklist that
    # itself requires this form would feed its own answer back.
    def checklist_doesnt_read_its_own_form
      return unless target_checklist? && checklist && !checklist_covered? && form_id

      uses = checklist.checklist_items.where(kind: "form_complete").any? { |item| Array(item.config["form_ids"]).include?(form_id) }
      errors.add(:base, "#{checklist.title} requires this form, so it can only ask everyone the checklist covers") if uses
    end
  end
end
