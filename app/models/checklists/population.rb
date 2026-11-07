module Checklists
  # Who a checklist covers, from its rules (those with no item): include or
  # exclude a team (and the teams below it, with or without managers), a
  # badge's holders, one person, or the applicants to a team (people with a
  # pending membership application to it or a team below it). With no include
  # rule it covers everyone in its team and below. Everyone covered is within
  # the checklist's team and below, except applicants, who are within the
  # team they applied to. Computed when needed, so people who join later are
  # covered.
  class Population
    attr_reader :checklist

    def initialize(checklist, rules: nil)
      @checklist = checklist
      @rules = rules
    end

    def rules
      @rules ||= checklist.checklist_rules.select { |rule| rule.item_id.nil? }
    end

    def person_ids
      @person_ids ||= begin
        reach = Checklists.team_subtree_ids(checklist.team_id)
        members = Membership.where(team_id: reach).distinct.pluck(:person_id)
        includes, excludes = rules.partition(&:effect_include?)

        included = if includes.empty?
          members
        else
          # Applicants count only through teams within the checklist's reach.
          applicants = includes.select { |rule| rule.target_applicants? && reach.include?(rule.team_id) }
            .flat_map { |rule| Population.rule_person_ids(rule) }
          (includes.reject(&:target_applicants?).flat_map { |rule| Population.rule_person_ids(rule) } & members) + applicants
        end
        (included.uniq - excludes.flat_map { |rule| Population.rule_person_ids(rule) }).sort
      end
    end

    # Of these people, the ones an item applies to: everyone, narrowed by the
    # item's include rules, less its exclude rules.
    def self.applicable_ids(item, person_ids, rules: nil)
      rules ||= item.checklist_rules.to_a
      return person_ids if rules.empty?

      includes, excludes = rules.partition(&:effect_include?)
      ids = includes.empty? ? person_ids : person_ids & includes.flat_map { |rule| rule_person_ids(rule) }
      ids - excludes.flat_map { |rule| rule_person_ids(rule) }
    end

    def self.rule_person_ids(rule)
      case rule.target_type
      when "team"
        memberships = Membership.where(team_id: Checklists.team_subtree_ids(rule.team_id))
        memberships = memberships.where(manager: false) unless rule.include_managers?
        memberships.distinct.pluck(:person_id)
      when "badge"
        holders = BadgeAssignment.where(badge_id: rule.badge_id)
        # With a team: only holders in that team or a team below it.
        holders = holders.where(person_id: Membership.where(team_id: Checklists.team_subtree_ids(rule.team_id)).select(:person_id)) if rule.team_id
        holders.distinct.pluck(:person_id)
      when "person" then [ rule.person_id ].compact
      when "applicants"
        MembershipApplication.pending.where(team_id: Checklists.team_subtree_ids(rule.team_id)).distinct.pluck(:person_id)
      else []
      end
    end
  end
end
