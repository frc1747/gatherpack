module Checklists
  # Recomputes a checklist's stored results (checklist_results) and reports
  # status changes. Runs from jobs (ChecklistRefreshJob, ChecklistClockJob,
  # ChecklistNightlyJob), never inside a user's save.
  #
  # A row whose status changed fires the "checklist_results - status
  # changed" hooks and the checklist_status_changed.gatherpack notification,
  # after the rows are written. A person's first computation is silent, as is
  # a silent: true run (a backfill), and nothing fires for a draft. A failing
  # hook or subscriber is logged and skipped. When a checklist's overall
  # changes, checklists that require it are marked for those people.
  #
  # Once a checklist has ended and its end-of-day answers are stored, only
  # recompute: true (the Recompute button) changes them. The first refresh
  # after the end always covers everyone, whoever it was asked about.
  class Refresher
    attr_reader :checklist

    def initialize(checklist, silent: false, recompute: false)
      @checklist = checklist
      @silent = silent
      @recompute = recompute
    end

    # Refreshes these people (everyone covered when nil) and returns the
    # changed result rows.
    def call(person_ids = nil)
      return [] if checklist.archived? || (checklist.results_frozen? && !@recompute)

      # A checklist's dates are days in the site's time zone; jobs run in UTC.
      Time.use_zone(Checklists.time_zone) { refresh(checklist.ended? ? nil : person_ids) }
    end

    private

    def refresh(person_ids)
      evaluator = Evaluator.new(checklist)
      covered = evaluator.covered_ids
      ids = person_ids.nil? ? covered : (Array(person_ids) & covered)
      computed = evaluator.call(ids)
      now = Time.current

      changes = ChecklistResult.transaction do
        changes = write(computed, now)
        gone = ChecklistResult.where(checklist_id: checklist.id).where.not(person_id: covered)
        gone = gone.where(person_id: person_ids) unless person_ids.nil?
        gone.delete_all
        checklist.update_columns(computed_at: now, next_refresh_at: evaluator.next_change_at)
        changes
      end

      announce(changes)
      mark_dependents(changes)
      changes
    end

    def write(computed, now)
      existing = ChecklistResult.where(checklist_id: checklist.id, person_id: computed.keys)
        .pluck(:item_id, :person_id, :id, :status, :previous_status, :changed_at)
        .to_h { |item_id, person_id, *rest| [ [ item_id, person_id ], rest ] }
      changed_keys = []

      rows = computed.flat_map do |person_id, by_item|
        by_item.map do |item_id, result|
          id, old_status, previous_status, changed_at = existing[[ item_id, person_id ]]
          old_status = ChecklistResult.statuses[old_status] if old_status
          previous_status = ChecklistResult.statuses[previous_status] if previous_status
          status = ChecklistResult.statuses.fetch(result.status)
          changed = old_status && old_status != status
          changed_keys << [ item_id, person_id ] if changed
          {
            id: id || SecureRandom.uuid, checklist_id: checklist.id, item_id: item_id, person_id: person_id,
            status: status, label: result.label, summary: result.summary, detail: result.detail,
            measures: result.measures, fix: result.fix, excuse: result.excuse,
            previous_status: changed ? old_status : previous_status,
            changed_at: changed || old_status.nil? ? now : changed_at,
            computed_at: now, stale: false
          }
        end
      end
      ChecklistResult.upsert_all(rows, unique_by: :index_checklist_results_on_checklist_item_person, update_only: rows.first.keys.excluding(:id)) if rows.any?

      return [] if changed_keys.empty?

      changed_keys.group_by(&:first).flat_map do |item_id, keys|
        ChecklistResult.where(checklist_id: checklist.id, item_id: item_id, person_id: keys.map(&:last)).to_a
      end
    end

    def announce(changes)
      return if @silent || !checklist.active? || changes.empty?

      hooks = Hook.where(event: STATUS_CHANGED_EVENT).to_a
      changes.each do |row|
        hooks.each do |hook|
          hook.run(row)
        rescue StandardError, ScriptError => e
          Rails.logger.error("Checklist hook #{hook.name.inspect} failed on #{row.id}: #{e.class}: #{e.message}")
        end
        begin
          ActiveSupport::Notifications.instrument(STATUS_CHANGED_NOTIFICATION, result: row, previous_status: row.previous_status)
        rescue StandardError => e
          Rails.logger.error("#{STATUS_CHANGED_NOTIFICATION} subscriber failed on #{row.id}: #{e.class}: #{e.message}")
        end
      end
    end

    def mark_dependents(changes)
      person_ids = changes.select { |row| row.item_id.nil? }.map(&:person_id)
      return if person_ids.empty?

      Checklists.mark(checklist.dependents.refreshable.to_a, person_ids)
    end
  end
end
