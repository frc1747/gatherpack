module Checklists
  # Shows existing commitments as checklists (checklists spec §11.1). For each
  # commitment without an item, up makes an active checklist with its title,
  # team and dates, population rules reproducing who owes it, the organizers
  # who still run it (Commitment#organizer?), and one count item linked to
  # it with its unit, amounts, pooling and counts-when. Then it computes the
  # new checklists' results, silently, so people see them at once.
  #
  # Who owes, progress, organizers and who sees what don't change. Who sees
  # a wrapped item and its checklist's overall is the commitment's rule, not
  # the read levels (Checklists::WrappedVisibility); the levels are set to the
  # count defaults of §10.1, which new count items use.
  #
  # Idempotent: a commitment that already has an item is skipped. down
  # removes the checklists holding wrapped items, with their items, and
  # never a commitment.
  #
  #   Checklists::WrapCommitments.new.up    # => the checklists made
  #   Checklists::WrapCommitments.new.down
  class WrapCommitments
    def up
      linked = ChecklistItem.where.not(commitment_id: nil).select(:commitment_id)
      checklists = Commitment.where.not(id: linked).includes(:commitment_organizers).order(:created_at).map { |commitment| wrap(commitment) }
      checklists.each { |checklist| Refresher.new(checklist.reload, silent: true).call }
      checklists
    end

    def down
      checklist_ids = ChecklistItem.where(wrapped: true).distinct.pluck(:checklist_id)
      Checklist.transaction { delete_checklists(checklist_ids) }
    end

    private

    # Plain deletes, not destroy: undoing the whole release runs this after
    # later migrations have dropped the columns that other features' destroy
    # guards read (sign-up position rules' and form audience rules'
    # checklist_id), so a callback would fail on a missing column. A row
    # elsewhere that still points at one of these checklists is refused by
    # its foreign key, as the guard would have refused it.
    def delete_checklists(ids)
      items = ChecklistItem.where(checklist_id: ids)
      ChecklistResult.where(checklist_id: ids).delete_all
      ChecklistRefresh.where(checklist_id: ids).delete_all
      ChecklistExcuse.where(item_id: items.select(:id)).delete_all
      ChecklistRule.where(checklist_id: ids).delete_all
      ChecklistGrant.where(checklist_id: ids).delete_all
      ChecklistOrganizer.where(checklist_id: ids).delete_all
      ChecklistList.where(checklist_id: ids).delete_all
      items.update_all(parent_id: nil, commitment_id: nil)
      items.delete_all
      Checklist.where(id: ids).delete_all
    end

    def wrap(commitment)
      Checklist.transaction do
        # The creator is set afterwards: a new checklist makes its creator an
        # organizer. Only organizers who can still run the commitment are
        # copied, so a lapsed organizer badge doesn't come back as full view.
        checklist = Checklist.create!(title: commitment.title, team_id: commitment.team_id, starts_on: commitment.starts_on,
          ends_on: commitment.ends_on, status: :active, read_level: "self_and_leaders", description: commitment.description)
        checklist.update_column(:created_by_id, commitment.created_by_id) if commitment.created_by_id
        commitment.commitment_organizers.includes(:person).each do |organizer|
          next unless commitment.organizer?(organizer.person)

          checklist.checklist_organizers.new(person_id: organizer.person_id).save!(validate: false)
        end

        item = checklist.checklist_items.new(kind: CountItem::COUNT, label: commitment.title, commitment: commitment, wrapped: true,
          exempt_label: "Doesn't owe", config: config_for(commitment), read_level: commitment.grouped? ? "group" : "self_and_leaders")
        item.save!
        rules_for(commitment, checklist)
        checklist
      end
    end

    def config_for(commitment)
      {
        "base_amount" => commitment.base_amount,
        "unit" => commitment.unit,
        "additional_amount" => commitment.additional_amount,
        "counts_when" => commitment.counts_when,
        "group_relationship_type_id" => commitment.group_relationship_type_id
      }.compact
    end

    # Who owes: the owing team, or, with an owing badge, the badge's holders
    # in the owing team (one badge rule limited to that team), less holders
    # of the exempt badge. Rules are written as they are, without the reach
    # checks a person's new rule gets: they describe people the commitment
    # already covers.
    def rules_for(commitment, checklist)
      if commitment.owing_badge_id
        add_rule(checklist, :include, :badge, badge_id: commitment.owing_badge_id, team_id: commitment.owing_team_id)
      else
        add_rule(checklist, :include, :team, team_id: commitment.owing_team_id, include_managers: true)
      end
      add_rule(checklist, :exclude, :badge, badge_id: commitment.exempt_badge_id) if commitment.exempt_badge_id
    end

    def add_rule(checklist, effect, target_type, **targets)
      checklist.checklist_rules.new(effect: effect, target_type: target_type, **targets).save!(validate: false)
    end
  end
end
