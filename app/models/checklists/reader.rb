module Checklists
  # Reads stored results for many people at once, with a computed fallback:
  # people with no stored rows yet are computed and stored (silently, as a
  # first computation); rows older than checklists_max_age_hours are
  # computed live for this read and marked for the refresh job, which then
  # reports any change.
  class Reader
    attr_reader :checklist, :viewer

    # as_of computes live as of that date, storing nothing (organizers' "as
    # of" picker), except where the checklist's frozen results are that
    # answer. pinned passes on that a frozen checklist is the one reading
    # (Context#pinned?).
    def initialize(checklist, viewer, as_of: nil, pinned: false)
      @checklist = checklist
      @viewer = viewer
      @as_of = as_of
      @pinned = pinned
    end

    # { person_id => Status } for the people the viewer may see.
    def status_for(people)
      ids = Array(people).map { |person| person.is_a?(Person) ? person.id : person }.uniq
      rows = rows_for(ids)
      visibility = Visibility.new(checklist, viewer).prepare(rows.keys)
      reasons = excuse_reasons(rows, visibility)

      # A row shows when its overall or any of its items reaches the viewer
      # (a pooled count seen by a relative, say); the overall shows only at
      # its own level, else it's nil.
      rows.each_with_object({}) do |(person_id, by_item), statuses|
        overall = build(nil, by_item[nil], person_id, visibility, reasons)
        built = build_items(items, by_item, person_id, visibility, reasons)
        overall = cap_overall(overall, by_item, person_id, visibility) if overall
        next if overall.nil? && built.empty?

        restrict_overall(overall, built) if overall && !(visibility.full? && built.size == items.size)
        statuses[person_id] = Status.new(person_id: person_id, overall: overall, items: built)
      end
    end

    # { person_id => status } of the overall, without visibility: for kinds
    # and predicates. People it doesn't cover are absent.
    def overall_statuses(person_ids)
      rows_for(person_ids).transform_values { |by_item| by_item[nil]&.status }.compact
    end

    # { person_id => { item_id => row } }, without visibility, from the same
    # read as overall_statuses (stored, or live where stored rows are too
    # old), for kinds that need more than the overall. People it doesn't
    # cover are absent.
    def rows(person_ids)
      rows_for(person_ids)
    end

    def items
      @items ||= checklist.top_level_items.includes(children: :children).to_a
    end

    private

    # { person_id => { item_id => row } }, rows being ChecklistResult or
    # live Result-backed stand-ins, for the covered people among ids.
    def rows_for(ids)
      return {} if ids.empty?
      return live_rows(ids, Evaluator.new(checklist, as_of: @as_of.in_time_zone.end_of_day, pinned: @pinned).call(ids)) if @as_of && !checklist.reads_stored_as_of?(@as_of)

      stored = ChecklistResult.where(checklist_id: checklist.id, person_id: ids).to_a.group_by(&:person_id)
      missing = ids - stored.select { |_, rows| rows.any? { |row| row.item_id.nil? } }.keys
      # People it doesn't cover never get rows; don't recompute for them.
      recomputable = !checklist.archived? && !checklist.results_frozen?
      missing &= Population.new(checklist).person_ids if missing.any? && recomputable
      if missing.any? && recomputable
        Refresher.new(checklist, silent: true).call(missing)
        ChecklistResult.where(checklist_id: checklist.id, person_id: missing).to_a.group_by(&:person_id).each { |id, rows| stored[id] = rows }
      end

      by_person = stored.transform_values { |rows| rows.index_by(&:item_id) }
      too_old = by_person.select { |_, rows| rows[nil] && rows[nil].computed_at < max_age.ago }.keys
      refresh_live(too_old, by_person) if too_old.any? && recomputable
      by_person.select { |_, rows| rows.key?(nil) }
    end

    def refresh_live(ids, by_person)
      computed = Evaluator.new(checklist).call(ids)
      by_person.merge!(live_rows(ids, computed, by_person))
      (ids - computed.keys).each { |id| by_person.delete(id) }
      Checklists.mark(checklist, ids)
    end

    # Unsaved result rows from computed results, keeping stored change times.
    def live_rows(ids, computed, stored_rows = {})
      computed.slice(*ids).to_h do |person_id, by_item|
        rows = by_item.to_h do |item_id, result|
          stored = stored_rows.dig(person_id, item_id)
          [ item_id, ChecklistResult.new(checklist_id: checklist.id, item_id: item_id, person_id: person_id, status: result.status,
            label: result.label, summary: result.summary, detail: result.detail, measures: result.measures, fix: result.fix,
            excuse: result.excuse, changed_at: stored&.changed_at, computed_at: Time.current) ]
        end
        [ person_id, rows ]
      end
    end

    def max_age
      hours = Settings[:checklists_max_age_hours].to_i
      (hours.positive? ? hours : 24).hours
    end

    def build_items(items, by_item, person_id, visibility, reasons)
      items.filter_map do |item|
        status = build(item, by_item[item.id], person_id, visibility, reasons)
        next unless status

        status.children = build_items(item.children.to_a, by_item, person_id, visibility, reasons)
        status
      end
    end

    def build(item, row, person_id, visibility, reasons)
      return unless row

      access = visibility.access(item, person_id)
      return unless access

      full = access == :full
      measures = full ? visible_measures(item, row.measures, person_id, visibility) : nil
      ItemStatus.new(item: item, status: row.status, word: (item || checklist).word_for(row.status), label: row.label,
        summary: full ? row.summary : nil, detail: full ? row.detail : nil, measures: measures,
        fix: full ? row.fix : nil, acts_for: visibility.acts_for(person_id), access: access,
        excuse: row.excuse && excuse_for(row.excuse, full, reasons), changed_at: row.changed_at, stale: row.stale)
    end

    # When an item's kind hides a counting item from this viewer, the overall
    # they see is worked out from the counting items they may see, so it
    # can't give the hidden answer away. (Items hidden only by their read
    # level still count: the overall has its own level.) When every counting
    # item is hidden from them, they don't see the overall at all.
    def cap_overall(overall, by_item, person_id, visibility)
      counting = items.select(&:counts?)
      shown = counting.select { |item| visibility.kind_allows?(item, person_id) }
      return overall if shown.size == counting.size
      return nil if shown.empty?

      statuses = shown.filter_map { |item| by_item[item.id]&.status }.reject { |status| status == "exempt" }
      status = if statuses.include?("not_met") then "not_met"
      elsif statuses.include?("pending") then "pending"
      else "met"
      end
      overall.status = status
      overall.word = checklist.word_for(status)
      overall.label = nil
      overall
    end

    # The overall's "n to do" counts only the counting items this viewer
    # sees, so neither it nor the report's order gives away hidden ones.
    def restrict_overall(overall, built)
      unmet = built.count { |entry| entry.item.counts? && (entry.not_met? || entry.pending?) }
      overall.measures = { "unmet" => unmet } if overall.full?
      overall.summary = overall.full? && unmet.positive? ? "#{unmet} to do" : nil
    end

    def visible_measures(item, measures, person_id, visibility)
      return measures if item.nil? || visibility.owner_measures?(person_id)

      kind = Checklists.item_kind(item.kind)
      owner_only = Array(kind&.measures).select(&:owner_only).map { |measure| measure.key.to_s }
      measures.except(*owner_only)
    end

    def excuse_for(excuse, full, reasons)
      return { "excused" => true } unless full

      { "by" => excuse["by"], "at" => excuse["at"], "expires_on" => excuse["expires_on"], "reason" => reasons[excuse["id"]],
        "id" => reasons.key?(excuse["id"]) ? excuse["id"] : nil }.compact
    end

    def excuse_reasons(rows, visibility)
      return {} unless visibility.manager?

      ids = rows.values.flat_map { |by_item| by_item.values.filter_map { |row| row.excuse&.dig("id") } }
      ids.any? ? ChecklistExcuse.where(id: ids).pluck(:id, :reason).to_h : {}
    end
  end
end
