# Whether an application may be approved yet. Only a registration with
# gate_approval holds approval back, until the applicant's overall on its
# checklist is done (met, or not counted for them). Someone the checklist
# doesn't cover hasn't finished it, so missing results never pass.
class Intake::ApprovalGate
  # Raised by MembershipApplication#approve! when the gate is shut, for
  # callers that didn't ask first.
  class Blocked < StandardError; end

  DONE = %w[met exempt].freeze

  attr_reader :application

  def initialize(application)
    @application = application
  end

  def applies?
    registration = application.registration
    registration&.gate_approval? && registration.active_checklist.present?
  end

  # Why approval has to wait, or nil when it needn't.
  def reason
    return unless applies?
    return if DONE.include?(status)

    name = application.person.first_name
    checklist = application.registration.checklist
    status ? "#{name} hasn't finished #{checklist.title}." : "#{checklist.title} doesn't cover #{name}."
  end

  # The applicant's overall on the checklist, worked out now
  # (MembershipApplication#intake_checklist_status), or nil when it doesn't
  # cover them.
  def status
    application.intake_checklist_status
  end
end
