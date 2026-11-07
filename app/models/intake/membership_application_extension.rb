# Included into MembershipApplication from config/initializers/intake.rb.
# An application remembers the registration it came from and how it was
# made (source), runs that registration's placement lists in the approval's
# transaction, and tells the applicant the decision. Applications made
# without a registration behave as before.
module Intake::MembershipApplicationExtension
  extend ActiveSupport::Concern

  included do
    belongs_to :registration, class_name: "Intake::Registration", optional: true, inverse_of: :membership_applications

    # request: asked from the team's page; link: a registration link; kiosk: a registration kiosk.
    enum :source, { request: 0, link: 1, kiosk: 2 }, prefix: true

    # The approving manager's pick from the registration's pick-one list and
    # their login (for which badges they may give), set before approve!, and
    # what placement added, set by it.
    attr_accessor :intake_pick_team, :intake_approver, :intake_placement

    after_create_commit { Intake.fire("membership_applications - submitted", self) }

    prepend Decisions
  end

  # Placement and notices run only while the feature is on, like its hooks.
  module Decisions
    def approve!
      intake = registration && Intake.enabled?
      transaction do
        super
        self.intake_placement = Intake::Placement.new(application: self, pick_team: intake_pick_team, approver: intake_approver).apply! if intake
      end
      Intake::Notices.approved(self) if intake
      Intake.fire("membership_applications - approved", self)
      true
    end

    # The reason, when given, is kept as reviewer_notes and sent to the applicant.
    def deny!(reason = nil)
      self.reviewer_notes = reason if reason.present?
      super()
      Intake::Notices.denied(self) if registration && Intake.enabled?
      Intake.fire("membership_applications - denied", self)
      true
    end
  end

  def intake_placement_preview
    Intake::Placement.new(application: self).preview
  end

  # Shown to managers next to the application.
  def intake_flags
    return [] unless registration
    flags = []
    flags << "Waiting for a guardian" if Intake.person_needs_guardian?(person) && !person.guardians.exists?
    member = Intake::HouseholdMember.where(person: person).where.not(role: :guardian).order(:created_at).last
    if (match = member&.possible_match)
      flags << "Might be the same person as #{match.display_name}"
    end
    entry = member&.entry
    if entry&.source_kiosk? && entry.verified_at.nil? && person.user&.intake_login_verified_at.nil?
      days = ((Time.current - entry.created_at) / 1.day).floor
      flags << "Email not opened (#{days} #{"day".pluralize(days)})" if days >= 3
    end
    flags
  end
end
