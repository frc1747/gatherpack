module Checklists
  # Computes results for a checklist: for each covered person, one Result per
  # item (children of groups included) and the overall, keyed by item id
  # (nil for the overall). Nothing is stored; Checklists::Refresher stores.
  #
  # items and rules may be drafts (unsaved, in memory), which is how the
  # live preview and the impact check evaluate a change before it's saved.
  #
  #   Checklists::Evaluator.new(checklist).call(person_ids)
  #   # => { person_id => { item_id => Result, nil => overall Result } }
  #
  # The overall: any counting item not met makes it not met; else any
  # pending makes it pending; else met. Exempt items are ignored.
  class Evaluator
    attr_reader :checklist, :context

    def initialize(checklist, as_of: nil, items: nil, rules: nil)
      @checklist = checklist
      @context = Context.new(checklist, as_of: as_of, evaluator: self)
      @items = items
      @rules = rules
    end

    # Top-level items, in order, with children loaded.
    def items
      @items ||= checklist.top_level_items.includes(:checklist_rules, children: [ :checklist_rules, { children: :checklist_rules } ]).to_a
    end

    def population
      @population ||= Population.new(checklist, rules: @rules)
    end

    def covered_ids
      population.person_ids
    end

    def call(person_ids = covered_ids)
      person_ids = person_ids.to_a & covered_ids
      results = evaluate_items(items, person_ids)

      person_ids.index_with do |person_id|
        row = all_items(items).to_h { |item| [ item.id, results.dig(item.id, person_id) ] }
        row[nil] = overall(items.select(&:counts?).map { |item| results.dig(item.id, person_id) })
        row
      end
    end

    # { item_id => { person_id => Result } } for these items and their
    # descendants, applying who each applies to and excuses.
    def evaluate_items(items, person_ids)
      items.each_with_object({}) do |item, results|
        item.id ||= SecureRandom.uuid
        evaluated = evaluate_item(item, person_ids)
        (@results ||= {}).merge!(evaluated)
        results.merge!(evaluated)
      end
    end

    # The earliest moment an answer can change with no data change: a kind's
    # own clock, the window's moving edge, the cutoff, an item's due date.
    def next_change_at
      now = context.as_of
      times = all_items(items).filter_map { |item| kind_for(item)&.next_change_at(item, context) }
      # "Within the last N" starts move at midnight.
      relative = checklist.starts_within_amount.present? || all_items(items).any? { |item| item.starts_within_amount.present? }
      times << now.to_date.tomorrow.in_time_zone.beginning_of_day if relative
      # An excuse stops applying the day after it expires.
      expiry = ChecklistExcuse.where(item_id: all_items(items).filter_map { |item| item.id if item.persisted? })
        .where(expires_on: now.to_date..).minimum(:expires_on)
      times << expiry.tomorrow.in_time_zone.beginning_of_day if expiry
      dates = [ checklist.cutoff_on, checklist.ends_on ] + all_items(items).flat_map { |item| [ item.ends_on, item.due_on ] }
      times += dates.compact.map { |date| date.tomorrow.in_time_zone.beginning_of_day }
      times.select { |time| time > now }.min
    end

    def kind_for(item)
      Checklists.item_kind(item.kind)
    end

    private

    def all_items(items)
      items.flat_map { |item| [ item ] + all_items(item.children.to_a) }
    end

    def evaluate_item(item, person_ids)
      kind = kind_for(item)
      applicable = Population.applicable_ids(item, person_ids)
      excuses = excuses_by_item.fetch(item.id, []).index_by(&:person_id)
      to_evaluate = applicable - excuses.keys
      results = {}

      if kind.nil?
        to_evaluate.each { |id| results[id] = Result.not_met("Unavailable", detail: "This kind of item isn't available here") }
      elsif to_evaluate.any?
        instance = kind.new(item, context)
        evaluated = instance.evaluate(to_evaluate)
        to_evaluate.each do |id|
          result = evaluated[id] || Result.not_met("Not checked")
          result.detail ||= instance.explain(result)
          result.label ||= "Missed" if item.due_on && item.due_on < context.as_of.to_date && !result.met? && !result.exempt?
          results[id] = result
        end
      end

      (person_ids - applicable).each { |id| results[id] = Result.exempt(item.exempt_label.presence || "Doesn't apply") }
      excuses.slice(*applicable).each do |id, excuse|
        results[id] = Result.exempt("Excused", excuse: { "id" => excuse.id, "by" => excuse.created_by&.display_name,
          "by_id" => excuse.created_by_id, "at" => excuse.created_at.to_date.iso8601, "expires_on" => excuse.expires_on&.iso8601 })
      end

      descendants = all_items(item.children.to_a)
      nested = if kind&.container?
        (@results || {}).slice(*descendants.map(&:id))
      else
        evaluate_items(item.children.to_a, person_ids)
      end
      nested.merge(item.id => results)
    end

    # Whole-item excuses in force on the as-of date, by item id.
    def excuses_by_item
      @excuses_by_item ||= ChecklistExcuse.whole_item.in_force(context.as_of.to_date)
        .where(item_id: all_items(items).filter_map { |item| item.id if item.persisted? })
        .includes(:created_by).group_by(&:item_id)
    end

    def overall(results)
      counted = results.compact.reject(&:exempt?)
      status = if counted.any?(&:not_met?) then "not_met"
      elsif counted.any?(&:pending?) then "pending"
      else "met"
      end
      unmet = counted.count { |result| !result.met? }
      Result.new(status: status, summary: unmet.zero? ? nil : "#{unmet} to do", measures: { "unmet" => unmet })
    end
  end
end
