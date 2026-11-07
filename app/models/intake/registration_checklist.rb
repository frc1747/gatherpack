# Included into Intake::Registration from config/initializers/intake_checklist.rb.
# A registration points to a checklist (checklists-spec.md) that the people
# joining through it work through; intake shows its results and defines no
# checks. With gate_approval on, an application is approved only once its
# person has finished the checklist (Intake::ApprovalGate).
module Intake::RegistrationChecklist
  extend ActiveSupport::Concern

  included do
    belongs_to :checklist, optional: true, inverse_of: :intake_registrations

    validate :gate_has_a_checklist
  end

  # The checklist, while both features are on. Nil otherwise, so nothing
  # about it shows and nothing waits on it.
  def active_checklist
    checklist if checklist && Intake.enabled? && Checklists.enabled?
  end

  # The teams people may apply to whose applicants the checklist doesn't
  # cover (no "Applicants to" rule for the team or a team above it), so the
  # setup page can say who won't see it.
  def checklist_uncovered_teams
    return [] unless checklist

    rules = checklist.population_rules.select { |rule| rule.effect_include? && rule.target_applicants? }
    covered = Checklists.team_subtree_ids(rules.map(&:team_id)) & Checklists.team_subtree_ids(checklist.team_id)
    apply_teams.reject { |team| covered.include?(team.id) }
  end

  private

  def gate_has_a_checklist
    errors.add(:gate_approval, "needs a checklist") if gate_approval? && checklist_id.blank?
  end
end
