# Included into MembershipApplication from config/initializers/intake_checklist.rb,
# after Intake::MembershipApplicationExtension. Approval checks the
# registration's gate first (Intake::ApprovalGate), and each decision keeps
# the checklist's state at the time with what placement stored, so the audit
# trail says what the person had done when they were approved or denied.
module Intake::ApplicationChecklist
  extend ActiveSupport::Concern

  included do
    prepend Decisions
  end

  module Decisions
    def approve!
      if pending? && (reason = Intake::ApprovalGate.new(self).reason)
        raise Intake::ApprovalGate::Blocked, reason
      end

      state = intake_checklist_state
      super.tap { intake_record_checklist_state(state) }
    end

    def deny!(...)
      state = intake_checklist_state
      super.tap { intake_record_checklist_state(state) }
    end
  end

  # { "id", "title", "status" } of the applicant's overall on the
  # registration's checklist, or nil without one.
  def intake_checklist_state
    checklist = registration&.active_checklist
    return unless checklist

    status = Intake::ApprovalGate.overall_status(checklist, person_id)
    { "id" => checklist.id, "title" => checklist.title, "status" => status || "not_covered" }
  end

  private

  def intake_record_checklist_state(state)
    update!(intake_placement: (intake_placement || {}).merge("checklist" => state)) if state
  end
end
