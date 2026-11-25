module Commitments
  # A copy of a commitment to adjust: its own fields (titled "<title> (copy)"),
  # organizers and sources in order. Adjustments are not copied, so the copy
  # starts with no credits added by hand. The copy is made by created_by, who
  # becomes one of its organizers, as for any new commitment.
  class Duplicator
    def initialize(commitment, created_by:)
      @commitment = commitment
      @created_by = created_by
    end

    def duplicate
      Commitment.transaction do
        copy = @commitment.dup
        copy.title = "#{@commitment.title} (copy)"
        copy.created_by = @created_by
        copy.save!
        copy_organizers(copy)
        copy_sources(copy)
        copy
      end
    end

    private

    # The original's organizers were checked when they were added, so they
    # keep their place without being checked again.
    def copy_organizers(copy)
      @commitment.commitment_organizers.order(:created_at).each do |organizer|
        next if copy.commitment_organizers.exists?(person_id: organizer.person_id)

        copy.commitment_organizers.new(person_id: organizer.person_id).save!(validate: false)
      end
    end

    # A source whose kind's branch isn't in the build still copies.
    def copy_sources(copy)
      @commitment.commitment_sources.each do |source|
        copy.commitment_sources.new(source.dup.attributes.except("id", "commitment_id", "created_at", "updated_at")).save!(validate: false)
      end
    end
  end
end
