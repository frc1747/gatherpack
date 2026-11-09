module Commitments
  # The hint next to each on-behalf-of choice in the sign up dialog
  # ("2 shifts left on Shifts"), one per commitment a sign-up to the slot
  # would count toward: one with a source for the slot's sheet or position,
  # whose period and team cover the slot's event. Shown only to viewers who
  # may see that progress anyway (PersonCommitmentsPolicy): the person,
  # someone in their group or related to it, and the commitment's organizers.
  #
  # With checklists on, a commitment that is a checklist's count item reads
  # as the item ("2 shifts left on Crew shifts (Eligibility)", the checklist
  # left out when it has the item's name) and is shown to whoever may see
  # the item for the person (checklists spec §10.1). With checklists off, or
  # without them, nothing here changes, wrapped commitments included.
  module SignupHint
    def self.call(sheet, person, viewer = SignupViewer.person, slot = SignupViewer.slot)
      return if person.nil? || viewer.nil? || slot.nil? || slot.signup_sheet != sheet || !GatherPack::Features.enabled?(:commitments)

      commitments_crediting(slot).filter_map do |commitment|
        next unless visible?(commitment, viewer, person)

        progress = commitment.progress_for(person)
        "#{progress.remaining} #{commitment.unit} left on #{name_for(commitment)}" if progress
      end.join("; ").presence
    end

    def self.commitments_crediting(slot)
      position = slot.signup_position
      event = slot.event
      kinds = Commitments.source_kinds.select { |_kind, klass| klass <= SignupSource }.keys
      sources = CommitmentSource.where(kind: kinds, subject_type: "SignupSheet", subject_id: position.signup_sheet_id)
        .or(CommitmentSource.where(kind: kinds, subject_type: "SignupPosition", subject_id: position.id))
      Commitment.where(id: sources.select(:commitment_id)).includes(:team, *item_includes).order(:starts_on, :title).select do |commitment|
        commitment.period_times.cover?(event.start_time) && commitment.team_and_below_ids.include?(event.team_id)
      end
    end

    # The checklist item behind the commitment, when checklists are on and
    # there is one. The wrap migration gives every existing commitment an
    # item whether or not the feature is on, so the flag decides.
    def self.item_for(commitment)
      commitment.checklist_item if checklists_on? && commitment.respond_to?(:checklist_item)
    end

    def self.item_includes
      checklists_on? && Commitment.reflect_on_association(:checklist_item) ? [ { checklist_item: :checklist } ] : []
    end

    def self.checklists_on?
      GatherPack::Features.enabled?(:checklists)
    end

    def self.name_for(commitment)
      item = item_for(commitment)
      return commitment.title unless item

      item.label == item.checklist.title ? item.label : "#{item.label} (#{item.checklist.title})"
    end

    def self.visible?(commitment, viewer, person)
      item = item_for(commitment)
      return item_visible?(item, viewer, person) if item

      viewer.id == person.id || commitment.group_ids_for(viewer.id).include?(person.id) ||
        commitment.group_relative_of?(viewer, person) || commitment.organizer?(viewer)
    end

    # The hint tells the remaining count, which is the item at full level.
    def self.item_visible?(item, viewer, person)
      Checklists::Visibility.new(item.checklist, viewer).access(item, person.id) == :full
    end
  end
end
