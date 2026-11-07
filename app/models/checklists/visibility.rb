module Checklists
  # What one viewer may see of a checklist's results (spec §10.1). Built
  # once per (checklist, viewer) and asked about many people: the lookups
  # behind it run once each, whatever the number of people.
  #
  # The viewer sees everything as an admin, a manager of the checklist's
  # team or a team above it, or one of its organizers. Otherwise, for each
  # person: the overall and items whose read level (AudienceLevels) reaches
  # the viewer, at full level; plus what a grant gives, at the grant's
  # access. Nothing else: such people aren't shown at all. On top of all of
  # that, an item's kind can hide a person's result from a viewer
  # (ItemKind.visible_to?), whoever they are.
  class Visibility
    attr_reader :checklist, :viewer

    def initialize(checklist, viewer)
      @checklist = checklist
      @viewer = viewer
    end

    def full?
      return @full if defined?(@full)

      # organizer? also rechecks that an organizer still holds a badge that
      # reaches the checklist's team.
      @full = viewer.present? && (manager? || checklist.organizer?(viewer))
    end

    # An admin, or a manager of the checklist's team or a team above it: who
    # may excuse, and read excuse reasons.
    def manager?
      return @manager if defined?(@manager)

      @manager = viewer.present? && (viewer.admin? ||
        Membership.where(person_id: viewer.id, manager: true, team_id: Checklists.team_ancestor_ids(checklist.team_id)).exists?)
    end

    # Narrows the lookups to these people (call before asking about many).
    def prepare(person_ids)
      @person_ids = person_ids
      @components = nil
      @kind_allowed = nil
      self
    end

    # The item's kind may cap who sees a person's result (ItemKind.visible_to?).
    def kind_allows?(item, person_id)
      return true if viewer.nil?

      kind = Checklists.item_kind(item.kind)
      return true if kind.nil?

      allowed = (@kind_allowed ||= {})[item.id] ||= kind.visible_person_ids(item, viewer, @person_ids || [ person_id ]).to_set
      allowed.include?(person_id) || (!@person_ids && kind.visible_person_ids(item, viewer, [ person_id ]).include?(person_id))
    end

    # :full, :status or nil for an item (nil item: the overall).
    def access(item, person_id)
      return nil if item && !kind_allows?(item, person_id)
      return :full if full?
      return nil if viewer.nil?

      level = item ? item.effective_read_level : checklist.read_level
      return :full if reaches?(item, level, person_id)

      grant_access(item)
    end

    # Whether the viewer sees anything of this person's row: the overall, or
    # any of these items.
    def row_visible?(person_id, items = [])
      access(nil, person_id).present? || items.any? { |item| access(item, person_id).present? }
    end

    # Owner-only measures: the person, their guardians and leaders.
    def owner_measures?(person_id)
      full? || (components_for(person_id) & %i[subject guardian leaders]).any?
    end

    # :self or :guardian, when the viewer is the person or acts for them.
    def acts_for(person_id)
      return :self if viewer && viewer.id == person_id
      :guardian if components_for(person_id).include?(:guardian)
    end

    def components_for(person_id)
      components.select { |_, ids| ids.include?(person_id) }.keys
    end

    private

    def reaches?(item, level, person_id)
      if level.to_s == "group"
        kind = item && Checklists.item_kind(item.kind)
        reach = kind&.group_reach(item, viewer, @person_ids || [ person_id ])
        return reach.include?(person_id) || leader?(person_id) if reach

        level = "family"
      end
      (AudienceLevels.components(level) & components_for(person_id)).any?
    end

    def leader?(person_id)
      components_for(person_id).include?(:leaders)
    end

    def components
      @components ||= %i[subject guardian leaders teammates].index_with do |component|
        people = AudienceLevels.component_people(component, viewer)
        people = people.where(id: @person_ids) if @person_ids
        people.pluck(:id).to_set
      end
    end

    def grant_access(item)
      accesses = grants.filter_map do |grant|
        next grant.access.to_sym if item.nil?
        next grant.access.to_sym if grant.item_ids.include?(item.id)
        next grant.access.to_sym if item.parent_id && grant.item_ids.include?(item.parent_id)
      end
      accesses.include?(:full) ? :full : accesses.first
    end

    def grants
      @grants ||= begin
        all = checklist.checklist_grants.to_a
        if all.empty?
          []
        else
          badge_ids = BadgeAssignment.where(person_id: viewer.id).pluck(:badge_id)
          team_ids = Checklists.team_ancestor_ids(Membership.where(person_id: viewer.id).pluck(:team_id))
          all.select { |grant| badge_ids.include?(grant.badge_id) || team_ids.include?(grant.team_id) }
        end
      end
    end
  end
end
