module Commitments
  # The hint next to each on-behalf-of choice in the sign up dialog when the
  # sheet feeds a commitment the person owes ("2 shifts left on Shifts"),
  # one per commitment that hasn't ended. Shown only to viewers who may see
  # that progress anyway (PersonCommitmentsPolicy): the person, someone in
  # their group or related to it, and the commitment's organizers.
  module SignupHint
    def self.call(sheet, person, viewer = SignupViewer.person)
      return if sheet.nil? || person.nil? || viewer.nil? || !GatherPack::Features.enabled?(:commitments)

      commitments_fed_by(sheet).filter_map do |commitment|
        next unless visible?(commitment, viewer, person)

        progress = commitment.progress_for(person)
        "#{progress.remaining} #{commitment.unit} left on #{commitment.title}" if progress
      end.join("; ").presence
    end

    def self.commitments_fed_by(sheet)
      kinds = Commitments.source_kinds.select { |_kind, klass| klass <= SignupSource }.keys
      sources = CommitmentSource.where(kind: kinds, subject_type: "SignupSheet", subject_id: sheet.id)
        .or(CommitmentSource.where(kind: kinds, subject_type: "SignupPosition", subject_id: sheet.signup_positions.select(:id)))
      Commitment.where(id: sources.select(:commitment_id), ends_on: Date.current..).order(:starts_on, :title)
    end

    def self.visible?(commitment, viewer, person)
      viewer.id == person.id || commitment.group_ids_for(viewer.id).include?(person.id) ||
        commitment.group_relative_of?(viewer, person) || commitment.organizer?(viewer)
    end
  end
end
