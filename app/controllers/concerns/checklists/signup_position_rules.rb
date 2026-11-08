module Checklists
  # Lets SignupPositionRulesController save checklist rules: permits their
  # settings and refuses a checklist the editor may not choose. Prepended by
  # config/initializers/checklists_signups.rb.
  module SignupPositionRules
    # The checklists someone may choose for a rule: active ones whose
    # overall they see for everyone it covers, since the rule then decides
    # by results nobody choosing it should be blind to (spec §10.1). That is
    # someone who runs the checklist, or a grant holder, whose view of the
    # overall no item's kind caps. Other organizers of the sheet see only
    # what they may (Checklists::SignupRule).
    def self.choices_for(user)
      person = user&.person
      return [] if person.nil?

      Checklist.active.order(:title).select { |checklist| sees_everyone?(checklist, person) }
    end

    # Item kinds cap what runners see too, so the cap check applies to
    # everyone; only reaching the overall differs.
    def self.sees_everyone?(checklist, person)
      return false unless Checklists::Visibility.new(checklist, person).full? || granted?(checklist, person)

      Checklists.capped_person_ids(checklist.top_level_items.to_a, person, Checklists::Population.new(checklist).person_ids).empty?
    end

    def self.granted?(checklist, person)
      badge_ids = BadgeAssignment.where(person_id: person.id).select(:badge_id)
      team_ids = Checklists.team_ancestor_ids(Membership.where(person_id: person.id).pluck(:team_id))
      checklist.checklist_grants.where(badge_id: badge_ids).or(checklist.checklist_grants.where(team_id: team_ids)).exists?
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
