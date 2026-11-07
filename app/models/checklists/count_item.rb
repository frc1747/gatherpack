module Checklists
  # Included in ChecklistItem (config/initializers/checklists_count.rb): a
  # count item keeps its Commitment row (checklists spec §11.2). Saving the
  # item creates the row the first time (team and owing team the checklist's,
  # titled with the item's label) and copies the item's settings and resolved
  # dates into it every time. The title is set once and never follows the
  # label, because reports find commitments by title (spec §11.1). Removing
  # the item removes its commitment; a copied item gets a new commitment
  # with the same sources (spec §9.3).
  module CountItem
    extend ActiveSupport::Concern

    COUNT = "count".freeze

    included do
      belongs_to :commitment, optional: true, inverse_of: :checklist_item

      validates :commitment_id, uniqueness: true, allow_nil: true
      validate :count_commitment_valid, if: :count?

      before_validation :default_count_exempt_label, if: :count?
      before_save :save_count_commitment, if: :count?
      after_destroy :destroy_count_commitment, if: :count?
    end

    def count?
      kind == COUNT
    end

    # The commitment as this item would leave it, unsaved.
    def count_commitment
      @count_commitment ||= commitment || Commitment.new(title: label, team_id: checklist&.team_id, owing_team_id: checklist&.team_id)
      @count_commitment.assign_attributes(Checklists::Kinds::Count.commitment_attributes(self))
      @count_commitment
    end

    # Memo for Checklists::Kinds::Count.group_reach, which visibility asks
    # once per person with the same arguments.
    def count_group_reach_cache
      @count_group_reach_cache ||= {}
    end

    def initialize_dup(other)
      super
      return unless count?

      @copied_from_commitment_id = other.commitment_id
      @count_commitment = nil
      self.commitment_id = nil
      self.wrapped = false
    end

    private

    def default_count_exempt_label
      self.exempt_label = "Doesn't owe" if exempt_label.blank?
    end

    def count_commitment_valid
      return if checklist.nil?

      record = count_commitment
      return if record.valid?

      record.errors.each do |error|
        next if %i[title starts_on ends_on].include?(error.attribute) && errors[:base].any?

        errors.add(:base, error.full_message)
      end
    end

    def save_count_commitment
      record = count_commitment
      created = record.new_record?
      # Unchanged, it isn't saved: a save fires "commitments - update" hooks.
      record.save! if created || record.changed?
      self.commitment = record
      copy_sources_from(@copied_from_commitment_id) if created && @copied_from_commitment_id
    end

    def copy_sources_from(commitment_id)
      CommitmentSource.where(commitment_id: commitment_id).order(:position, :created_at).each do |source|
        commitment.commitment_sources.create!(source.attributes.slice("kind", "subject_type", "subject_id", "per", "credits", "max_credits", "position"))
      end
    end

    def destroy_count_commitment
      Commitment.find_by(id: commitment_id)&.destroy! if commitment_id
    end
  end
end
