# Copies a source's records into AccountingRecord: a full read, the
# changes since the last check, or one record. Works through
# Accounting::Provider only, so it's the same for every source.
class Accounting::Sync
  # The changes job starts a little before the last check, so a record
  # saved while the last one ran isn't missed. Seeing it twice costs
  # nothing: its revision hasn't changed.
  OVERLAP = 1.minute

  attr_reader :source

  def initialize(source)
    @source = source
  end

  # Reads every record of every type; records the source no longer has are
  # marked deleted. Returns the records saved.
  def full
    started = Time.current
    saved = []

    source.entity_types.each_key do |entity_type|
      seen = []
      source.each_record(entity_type) do |data|
        seen << source.external_id(entity_type, data)
        record = upsert(entity_type, data)
        saved << record if record
      end
      mark_missing_deleted(entity_type, seen)
    end

    finish(saved, everyone: true)
    source.record_state!(last_full_sync_at: started, last_change_check_at: started - OVERLAP, last_error: nil)
    saved
  end

  # The changes since the last check; a full read instead when there's been
  # no check yet or the last one is further back than the source's change
  # feed reaches. Returns the records saved.
  def changes
    since = source.last_change_check_time
    window = source.change_window
    return full if since.nil? || (window && since < window.ago)

    started = Time.current
    saved = []
    types = source.entity_types.keys

    source.each_change(types, since) do |entity_type, data, deleted|
      next unless types.include?(entity_type)

      if deleted
        mark_deleted(entity_type, [ source.external_id(entity_type, data) ])
      else
        record = upsert(entity_type, data)
        saved << record if record
      end
    end

    finish(saved)
    source.record_state!(last_change_check_at: started - OVERLAP, last_error: nil)
    saved
  end

  # One part of the source read again, such as one ledger: saves each of
  # rows ([entity_type, data] pairs) and marks the records in held (the
  # part's records) that rows no longer has deleted. Returns the records saved.
  def part(rows, held)
    saved = []
    seen = Hash.new { |hash, key| hash[key] = [] }

    rows.each do |entity_type, data|
      seen[entity_type] << source.external_id(entity_type, data)
      record = upsert(entity_type, data)
      saved << record if record
    end
    held.current.distinct.pluck(:entity_type).each do |entity_type|
      gone = held.current.where(entity_type: entity_type).where.not(external_id: seen[entity_type]).pluck(:external_id)
      mark_deleted(entity_type, gone) if gone.any?
    end

    finish(saved)
    saved
  end

  # One record a notification named; marked deleted when the source no
  # longer has it.
  def fetch(entity_type, external_id)
    return [] unless source.entity_types.key?(entity_type)

    data = source.fetch_record(entity_type, external_id)
    return delete(entity_type, [ external_id ]) if data.nil?

    saved = [ upsert(entity_type, data) ].compact
    finish(saved)
    saved
  end

  # Saves one raw record with its neutral columns, unless it's unchanged
  # (same revision, or the same data for a source without revisions).
  # Returns the record when saved, else nil.
  def upsert(entity_type, data)
    external_id = source.external_id(entity_type, data)
    revision = source.revision(entity_type, data)
    record = source.accounting_records.find_or_initialize_by(entity_type: entity_type, external_id: external_id)
    return nil if record.persisted? && !record.deleted? && unchanged?(record, revision, data)

    record.assign_attributes(neutral_defaults.merge(source.normalize(entity_type, data).slice(*AccountingRecord::NEUTRAL_COLUMNS)))
    record.assign_attributes(data: data, revision: revision, deleted_at: nil, fetched_at: Time.current)
    source.prepare_record(record)
    record.save!
    record
  end

  # Records the source says are gone (a notification, a fetch that found
  # nothing): marked deleted, then their people's rules are queued. Returns
  # no records saved.
  def delete(entity_type, external_ids)
    mark_deleted(entity_type, external_ids)
    finish([])
    []
  end

  # Marks records deleted. Not a new revision, so no record hooks fire.
  # Callers queue evaluation through #finish (or use #delete).
  def mark_deleted(entity_type, external_ids)
    now = Time.current
    deleted = source.accounting_records.current.where(entity_type: entity_type, external_id: external_ids)
    touched_customers.merge(deleted.where.not(customer_external_id: nil).pluck(:customer_external_id))
    deleted.update_all(deleted_at: now, updated_at: now)
  end

  private
    # Lets the source fill columns from other records, makes the automatic
    # customer links, then queues the source's rules for the people whose
    # records changed (everyone, after a full read).
    def finish(saved, everyone: false)
      source.after_sync(saved)
      links = Accounting::CustomerLinks.new(source)
      links.after_sync(saved)

      if everyone
        Accounting::EvaluateRuleJob.for_source(source)
      else
        customer_ids = touched_customers + saved.filter_map(&:customer_external_id)
        Accounting::EvaluateRuleJob.for_source(source, customer_ids.flat_map { |id| links.people_for(id).ids }.uniq)
      end
    end

    # Customers of records marked deleted, whose people need evaluating.
    def touched_customers
      @touched_customers ||= Set.new
    end

    def mark_missing_deleted(entity_type, seen)
      now = Time.current
      source.accounting_records.current.where(entity_type: entity_type).where.not(external_id: seen).update_all(deleted_at: now, updated_at: now)
    end

    def unchanged?(record, revision, data)
      revision.present? ? record.revision == revision : record.data == data
    end

    # A column normalize leaves out goes back to its default, so nothing
    # from an earlier revision lingers.
    def neutral_defaults
      AccountingRecord.column_defaults.symbolize_keys.slice(*AccountingRecord::NEUTRAL_COLUMNS)
    end
end
