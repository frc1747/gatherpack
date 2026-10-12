module Commitments
  # The hint next to each on-behalf-of choice in the sign up dialog
  # ("2 shifts left on Shifts"), one per commitment a sign-up to the slot
  # would count toward: one with a source for the slot's sheet or position,
  # whose period and team cover the slot's event. Shown only to viewers who
  # may see that progress anyway (PersonCommitmentsPolicy): the person,
  # someone in their group or related to it, and the commitment's organizers.
  module SignupHint
    def self.call(sheet, person, viewer = SignupViewer.person, slot = SignupViewer.slot)
      return if person.nil? || viewer.nil? || slot.nil? || slot.signup_sheet != sheet || !GatherPack::Features.enabled?(:commitments)

      commitments_crediting(slot).filter_map do |commitment|
        next unless visible?(commitment, viewer, person)

        progress = commitment.progress_for(person)
        "#{progress.remaining} #{commitment.unit} left on #{commitment.title}" if progress
      end.join("; ").presence
    end

    def self.commitments_crediting(slot)
      position = slot.signup_position
      event = slot.event
      kinds = Commitments.source_kinds.select { |_kind, klass| klass <= SignupSource }.keys
      sources = CommitmentSource.where(kind: kinds, subject_type: "SignupSheet", subject_id: position.signup_sheet_id)
        .or(CommitmentSource.where(kind: kinds, subject_type: "SignupPosition", subject_id: position.id))
      Commitment.where(id: sources.select(:commitment_id)).includes(:team).order(:starts_on, :title).select do |commitment|
        commitment.period_times.cover?(event.start_time) && commitment.team_and_below_ids.include?(event.team_id)
      end
    end

    def self.visible?(commitment, viewer, person)
      viewer.id == person.id || commitment.group_ids_for(viewer.id).include?(person.id) ||
        commitment.group_relative_of?(viewer, person) || commitment.organizer?(viewer)
    end
  end
end
