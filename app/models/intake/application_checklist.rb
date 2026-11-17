# Included into MembershipApplication from config/initializers/intake_checklist.rb,
# after Intake::MembershipApplicationExtension. Approval checks the
# registration's gate first (Intake::ApprovalGate), and each decision keeps
# the checklist's state at the time in intake_placement, written with the
# decision itself, so the audit trail and the decision's hooks say what the
# person had done when they were approved or denied.
module Intake::ApplicationChecklist
  extend ActiveSupport::Concern

  included do
    # Set by preload_intake_checklist_statuses; worked out on first use
    # otherwise.
    attr_writer :intake_checklist_status

    prepend Decisions
  end

  class_methods do
    # Works out the applicants' overalls with one evaluation per checklist,
    # for deciding many applications at once.
    def preload_intake_checklist_statuses(applications)
      applications = applications.to_a
      ActiveRecord::Associations::Preloader.new(records: applications, associations: { registration: :checklist }).call
      applications.group_by { |application| application.registration&.active_checklist }.each do |checklist, group|
        next unless checklist

        results = Checklists::Evaluator.new(checklist).call(group.map(&:person_id).uniq)
        group.each { |application| application.intake_checklist_status = results.dig(application.person_id, nil)&.status }
      end
      applications
    end
  end

  module Decisions
    def approve!
      if pending? && (reason = Intake::ApprovalGate.new(self).reason)
        raise Intake::ApprovalGate::Blocked, reason
      end

      intake_keep_checklist_state
      super
    end

    def deny!(...)
      intake_keep_checklist_state
      super
    end
  end

  # The applicant's overall on the registration's checklist, worked out now
  # rather than read from stored results, which may be waiting for their
  # refresh after a change: a decision goes by what's true when it's made.
  # Nil without a checklist, or when it doesn't cover them.
  def intake_checklist_status
    return @intake_checklist_status if defined?(@intake_checklist_status)

    checklist = registration&.active_checklist
    @intake_checklist_status = checklist && Checklists::Evaluator.new(checklist).call([ person_id ]).dig(person_id, nil)&.status
  end

  # { "id", "title", "status" } of the applicant's overall on the
  # registration's checklist, or nil without one.
  def intake_checklist_state
    checklist = registration&.active_checklist
    return unless checklist

    { "id" => checklist.id, "title" => checklist.title, "status" => intake_checklist_status || "not_covered" }
  end

  private

  # Saved by the decision's own update (upstream's approve! and deny! save
  # the record; intake's placement merges into it).
  def intake_keep_checklist_state
    state = intake_checklist_state
    self.intake_placement = (intake_placement || {}).merge("checklist" => state) if state
  end
end
