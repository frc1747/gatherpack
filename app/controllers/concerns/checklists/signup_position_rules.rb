module Checklists
  # Lets SignupPositionRulesController save checklist rules: permits their
  # settings and refuses a checklist the editor may not choose. Prepended by
  # config/initializers/checklists_signups.rb.
  module SignupPositionRules
    # The checklists someone may choose for a rule: active ones whose
    # overall they see for everyone it covers, since the rule shows anyone
    # who runs the sheet whether a person passes (spec §10.1). That is
    # someone who runs the checklist, or a grant holder whose view of the
    # overall no item hides.
    def self.choices_for(user)
      person = user&.person
      return [] if person.nil?

      Checklist.active.order(:title).select { |checklist| sees_everyone?(checklist, person) }
    end

    def self.sees_everyone?(checklist, person)
      return true if Checklists::Visibility.new(checklist, person).full?

      badge_ids = BadgeAssignment.where(person_id: person.id).select(:badge_id)
      team_ids = Checklists.team_ancestor_ids(Membership.where(person_id: person.id).pluck(:team_id))
      granted = checklist.checklist_grants.where(badge_id: badge_ids).or(checklist.checklist_grants.where(team_id: team_ids)).exists?
      granted && Checklists.capped_person_ids(checklist.top_level_items.to_a, person, Checklists::Population.new(checklist).person_ids).empty?
    end

    private

    def rule_params
      super.merge(params.require(:signup_position_rule).permit(:checklist_id, :accept_pending))
    end

    def teams_out_of_reach?
      super || checklist_out_of_reach?
    end

    def refuse_teams
      return super unless checklist_out_of_reach?

      redirect_to edit_path, alert: "Pick an active checklist whose results you can see for everyone.", status: :see_other
    end

    # Only a newly chosen checklist is checked, so another organizer can
    # still change an existing rule's other settings.
    def checklist_out_of_reach?
      return @checklist_out_of_reach if defined?(@checklist_out_of_reach)

      @checklist_out_of_reach = @rule.checklist? && @rule.checklist_id.present? && @rule.checklist_id_changed? &&
        Checklists::SignupPositionRules.choices_for(current_user).none? { |checklist| checklist.id == @rule.checklist_id }
    end
  end
end
