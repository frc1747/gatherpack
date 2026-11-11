module Checklists
  # A form's "have finished" or "haven't finished" checklist rule needs the
  # form in the checklist's team or a team below it (FormAudienceTarget).
  # Moving the form, or the checklist, so that no longer holds is refused
  # while such a rule exists, so the rule can't quietly ask nobody and
  # Duplicate can still copy it.
  #
  # Moving a team under another parent isn't guarded: a rule left outside
  # the checklist's team then asks nobody (its description says it's
  # ignored) and Duplicate refuses to copy it. That's accepted, so teams
  # carry no checklist rules.
  module FormAudienceTeamGuard
    # The rules of these forms or checklists that ask by finished or not.
    def self.status_rules(scope)
      scope.where(target_type: :checklist).where.not(checklist_match: :covered).includes(:form, :checklist)
    end

    def self.message(rules)
      titles = rules.map { |rule| rule.checklist&.title }.compact.uniq
      "can't change while the audience asks people who have or haven't finished #{titles.to_sentence}; " \
        "ask everyone #{titles.one? ? "it covers" : "they cover"} first"
    end

    # Included in Form.
    module OnForm
      extend ActiveSupport::Concern

      included do
        validate :team_keeps_checklist_rules, on: :update
      end

      private

      def team_keeps_checklist_rules
        return unless will_save_change_to_team_id? && team_id

        rules = FormAudienceTeamGuard.status_rules(form_audience_rules).select do |rule|
          rule.checklist && !Checklists.team_subtree_ids(rule.checklist.team_id).include?(team_id)
        end
        errors.add(:team_id, FormAudienceTeamGuard.message(rules)) if rules.any?
      end
    end

    # Included in Checklist.
    module OnChecklist
      extend ActiveSupport::Concern

      included do
        validate :team_keeps_form_rules, on: :update
      end

      private

      def team_keeps_form_rules
        return unless will_save_change_to_team_id? && team_id

        subtree = Checklists.team_subtree_ids(team_id)
        rules = FormAudienceTeamGuard.status_rules(FormAudienceRule.where(checklist_id: id)).reject { |rule| rule.form.nil? || subtree.include?(rule.form.team_id) }
        return if rules.empty?

        errors.add(:team_id, "can't change while #{rules.map { |rule| rule.form.title }.uniq.to_sentence} " \
          "#{rules.one? ? "asks" : "ask"} people who have or haven't finished it; those forms must stay in its team or below")
      end
    end
  end
end
