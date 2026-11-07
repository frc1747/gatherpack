# Checklists: what a person must have, do or be, answered for everyone a
# checklist covers as done (met), almost (pending), not yet (not_met) or not
# counted (exempt).
#
# Item kinds are the extension point. A kind is a Checklists::ItemKind
# subclass, registered from an initializer so a branch can add one without
# touching this code:
#
#   Checklists.register_item_kind(:badge, Checklists::Kinds::Badge)
#
# An item whose kind isn't registered shows as unavailable and counts as not
# met, never as a silent pass.
#
# The API for other features (results come from stored rows, see
# Checklists::Refresher; visibility is applied inside, so a caller can't
# over-show):
#
#   Checklists.status_for(checklist, people, viewer:)  # { person_id => Checklists::Status }
#   Checklists.checklist_for(person, viewer: person)   # [[checklist, Checklists::Status], ...]
#   Checklists.meets?(checklist, person, accept: :met) # strict by default (met or exempt)
#   Checklists.people_meeting(checklist, accept: :met) # a Person relation
#   Checklists.people_covered_by(checklist)            # a Person relation
module Checklists
  STATUSES = %w[met pending not_met exempt].freeze

  # The words people see when a checklist doesn't set its own.
  DEFAULT_WORDS = { "met" => "Done", "pending" => "Almost", "not_met" => "Not yet", "exempt" => "Not counted" }.freeze

  # Who may see an item or a checklist's overall, relative to the person it's
  # about (Checklists::Visibility). group is for pooled kinds; a kind that
  # doesn't pool treats it as family.
  READ_LEVELS = {
    "self_and_leaders" => "The person and their leaders",
    "guardians" => "Their guardians and leaders",
    "family" => "The person, their guardians and leaders",
    "team" => "Also their teammates",
    "group" => "Their group (people pooled with them) and leaders"
  }.freeze

  STATUS_CHANGED_EVENT = "checklist_results - status changed".freeze
  STATUS_CHANGED_NOTIFICATION = "checklist_status_changed.gatherpack".freeze

  # Models with hook targets ("<table> - create/update/destroy").
  HOOK_TARGETS = %w[checklists checklist_items checklist_rules checklist_grants checklist_organizers
    checklist_excuses checklist_attestations checklist_lists].freeze

  @kinds = {}

  class << self
    def enabled?
      GatherPack::Features.enabled?(:checklists)
    end

    def register_item_kind(kind, klass)
      @kinds[kind.to_s] = klass
      Checklists::Invalidation.install(klass)
      Checklists::ProtectsReferences.install(klass)
    end

    def unregister_item_kind(kind)
      @kinds.delete(kind.to_s)
    end

    # The kind's class, or nil when it isn't registered.
    def item_kind(kind)
      @kinds[kind.to_s]
    end

    def item_kinds
      @kinds.dup
    end

    def word_for(status)
      DEFAULT_WORDS.fetch(status.to_s)
    end

    def status_for(checklist, people, viewer:)
      Checklists::Reader.new(checklist, viewer).status_for(people)
    end

    # Every checklist covering this person (from stored results) that the
    # viewer may see, with the person's status in each. Archived checklists
    # are left out, and drafts too unless the viewer runs them.
    def checklist_for(person, viewer: person)
      return [] if person.nil? || viewer.nil?

      ids = ChecklistResult.where(person_id: person.id, item_id: nil).select(:checklist_id)
      Checklist.where(id: ids).where.not(status: :archived).order(:title).filter_map do |checklist|
        next if checklist.draft? && !checklist.organizer?(viewer)

        status = status_for(checklist, [ person ], viewer: viewer)[person.id]
        [ checklist, status ] if status
      end
    end

    # Whether the person finishes the checklist. accept: :met counts a met or
    # exempt overall (an item that doesn't apply to them already counts as
    # done inside it); pass [:met, :pending] where signing up is the way to
    # finish. Someone the checklist doesn't cover never meets it.
    def meets?(checklist, person, accept: :met)
      people_meeting(checklist, accept: accept).exists?(id: person.id)
    end

    def people_meeting(checklist, accept: :met)
      checklist.people_meeting(accept: accept)
    end

    def people_covered_by(checklist)
      Person.where(id: Checklists::Population.new(checklist).person_ids)
    end

    # Marks people's stored results for recomputation and queues one refresh
    # per checklist, 30 seconds out, so a burst of changes is one run.
    # person_ids :all marks the whole checklist.
    def mark(checklists, person_ids)
      checklists = Array(checklists)
      return if checklists.empty?

      now = Time.current
      ids = person_ids == :all ? [ nil ] : Array(person_ids).compact.uniq
      return if ids.empty?

      checklists.each do |checklist|
        queued = ChecklistRefresh.where(checklist_id: checklist.id).exists?
        ChecklistRefresh.insert_all(ids.map { |id| { checklist_id: checklist.id, person_id: id, created_at: now } },
          unique_by: %i[checklist_id person_id])
        stale = ChecklistResult.where(checklist_id: checklist.id)
        stale = stale.where(person_id: ids) unless person_ids == :all
        stale.update_all(stale: true)
        ChecklistRefreshJob.set(wait: 30.seconds).perform_later(checklist.id) unless queued
      end
    end

    # The teams with these ids and every team below them, in one query.
    def team_subtree_ids(team_ids)
      team_tree_ids(team_ids, "teams.parent_id = tree.id")
    end

    # The teams with these ids and every team above them, in one query.
    def team_ancestor_ids(team_ids)
      team_tree_ids(team_ids, "teams.id = tree.parent_id")
    end

    # The ids among person_ids whose result on this item the viewer may see
    # under its kind's cap (ItemKind.visible_to?) and the caps of every item
    # inside it: a group whose answer could come from a capped child is
    # capped too.
    def visible_person_ids(item, viewer, person_ids)
      ([ item ] + descendants_of(item)).reduce(person_ids.to_a) do |ids, entry|
        kind = item_kind(entry.kind)
        kind && ids.any? ? kind.visible_person_ids(entry, viewer, ids) : ids
      end
    end

    # The ids among person_ids whose overall depends on a counting item
    # (among these top-level items) whose kind hides it from the viewer.
    def capped_person_ids(items, viewer, person_ids)
      return [] if viewer.nil? || person_ids.empty?

      items.select(&:counts?).flat_map { |item| person_ids - visible_person_ids(item, viewer, person_ids) }.uniq
    end

    # Whether the two are related by any relationship, which rules out
    # excusing or attesting for each other.
    def related?(person, other)
      return false if person.nil? || other.nil?

      Relationship.where(parent_id: person.id, child_id: other.id)
        .or(Relationship.where(parent_id: other.id, child_id: person.id)).exists?
    end

    private

    def descendants_of(item)
      item.children.to_a.flat_map { |child| [ child ] + descendants_of(child) }
    end

    def team_tree_ids(team_ids, join)
      team_ids = Array(team_ids).compact
      return [] if team_ids.empty?

      sql = ActiveRecord::Base.sanitize_sql([ <<~SQL.squish, { ids: team_ids } ])
        WITH RECURSIVE tree(id, parent_id) AS (
          SELECT id, parent_id FROM teams WHERE id IN (:ids)
          UNION
          SELECT teams.id, teams.parent_id FROM teams JOIN tree ON #{join}
        )
        SELECT id FROM tree
      SQL
      ActiveRecord::Base.connection.select_values(sql)
    end
  end
end
