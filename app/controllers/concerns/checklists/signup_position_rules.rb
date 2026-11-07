module Checklists
  # Lets SignupPositionRulesController save checklist rules: permits their
  # settings and refuses a checklist the editor can't see or that's
  # archived. Prepended by config/initializers/checklists_signups.rb.
  module SignupPositionRules
    # The checklists someone may choose for a rule: those they can see,
    # not archived.
    def self.choices_for(user)
      ChecklistPolicy::Scope.new(user, Checklist).resolve.where.not(status: :archived).order(:title)
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

      redirect_to edit_path, alert: "Pick a checklist you can see.", status: :see_other
    end

    # Only a newly chosen checklist is checked, so another organizer can
    # still change an existing rule's other settings.
    def checklist_out_of_reach?
      @rule.checklist? && @rule.checklist_id.present? && @rule.checklist_id_changed? &&
        !Checklists::SignupPositionRules.choices_for(current_user).exists?(id: @rule.checklist_id)
    end
  end
end
