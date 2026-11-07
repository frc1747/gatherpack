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
    # their login (for which badges they may give), set before approve!.
    # What placement added is stored with the decision (intake_placement).
    attr_accessor :intake_pick_team, :intake_approver

    after_create_commit { Intake.fire("membership_applications - submitted", self) }

    prepend Decisions
  end

  # Placement and notices run only while the feature is on, like its hooks.
  module Decisions
    def approve!
      intake = registration && Intake.enabled?
      transaction do
        super
        if intake
          added = Intake::Placement.new(application: self, pick_team: intake_pick_team, approver: intake_approver).apply!
          update!(intake_placement: added.merge(approved_by_id: intake_approver&.person&.id, approved_at: Time.current))
        end
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

  # "Added to Everyone and Class of 2031; gave Joined Online", from what
  # placement stored with the approval.
  def intake_placement_summary
    added = intake_placement || {}
    parts = []
    parts << "added to #{Array(added["teams"]).to_sentence}" if Array(added["teams"]).any?
    parts << "gave #{Array(added["badges"]).to_sentence}" if Array(added["badges"]).any?
    parts << "guardians added to #{Array(added["guardian_teams"]).to_sentence}" if Array(added["guardian_teams"]).any?
    parts.join("; ").upcase_first.presence
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
