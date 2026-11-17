module Housekeeping
  # One registered kind of record (Housekeeping.register). Options:
  #
  # - ended_on: when the record ended or closed, as SQL so lists filter in
  #   the database: a column (Symbol), columns whose first present value
  #   counts ([:end_time, :start_time], a COALESCE), or an SQL expression
  #   (String) on the model's table. NULL when it hasn't ended.
  # - ended_type: :date or :datetime, for a String ended_on. Columns say
  #   their own.
  # - archived: ->(scope) { the archived ones }. Default: archived_at is set.
  # - archive / restore: ->(record) { ... }. Default: set or clear archived_at.
  # - used_by: ->(record) { [names] } of what still uses it; such a record is
  #   skipped when archiving. Default: the checklists that would stop it
  #   being deleted (Checklists::ProtectsReferences), when it has those.
  # - permitted: ->(user, record, action) { true/false } for :archive,
  #   :restore and :copy. Default: the record's policy update? (and, for
  #   :copy, create?).
  # - copy: a class like Checklists::Copier: new(record, shift_months:),
  #   #date_changes, #replacements and #call(title:, by:, replace:) making a
  #   draft. Without it the type can't be copied.
  # - available: -> { true/false }, usually its feature's switch.
  # - auto_archive: false when the type archives itself on its own schedule
  #   (no "Archive automatically" setting here).
  # - auto_scope: ->(scope) { the ones automatic archiving may touch }, such
  #   as only active checklists (not drafts). Default: every unarchived one.
  # - fallback_setting: an older setting read while the "Archive
  #   automatically" one is blank: a number of days, or a date (YYYY-MM-DD)
  #   meaning "ended before it". It's also the only one read while
  #   Housekeeping is off, so a type that archived itself before keeps doing
  #   so (Housekeeping.run_fallback).
  # - label: the plural shown on screens. Default: the model's.
  # - list_path: the route helper of its list page, for a link back.
  class Type
    attr_reader :model, :key, :label, :list_path, :copier

    def initialize(model, key: nil, label: nil, ended_on:, ended_type: :datetime, archived: nil, archive: nil, restore: nil,
      used_by: nil, permitted: nil, copy: nil, available: nil, auto_archive: true, auto_scope: nil, fallback_setting: nil, list_path: nil)
      @model = model
      @key = (key || model.table_name).to_s
      @label = label || model.model_name.human.pluralize
      @ended_on = ended_on
      @ended_type = ended_type
      @fallback_setting = fallback_setting
      @auto_scope = auto_scope
      @archived = archived
      @archive = archive
      @restore = restore
      @used_by = used_by
      @permitted = permitted
      @copier = copy
      @available = available
      @auto_archive = auto_archive
      @list_path = list_path
    end

    def available?
      Housekeeping.enabled? && (@available.nil? || @available.call)
    end

    def auto_archive?
      @auto_archive
    end

    def copyable?
      !@copier.nil?
    end

    def setting
      :"housekeeping_archive_#{key}_after_days"
    end

    # Days after its end that a record is archived automatically; nil: never.
    def auto_archive_days
      value = Settings[setting].to_s.strip
      value.to_i if value.match?(/\A\d+\z/)
    end

    def fallback_setting?
      !@fallback_setting.nil?
    end

    # Records that ended on or before this date are due to be archived
    # automatically; nil: never. From the setting, or the fallback setting
    # while it's blank. With Housekeeping off, only the fallback setting.
    def auto_archive_cutoff(today = Date.current)
      days = Housekeeping.enabled? ? auto_archive_days : nil
      return today - days.days - 1.day if days
      return if @fallback_setting.nil?

      value = Settings[@fallback_setting].to_s.strip
      if value.match?(/\A\d+\z/)
        today - value.to_i.days - 1.day
      elsif value.present?
        Date.iso8601(value) - 1.day
      end
    rescue Date::Error
      nil
    end

    def ended_on(record)
      columns = Array(@ended_on) if @ended_on.is_a?(Symbol) || @ended_on.is_a?(Array)
      value = columns ? columns.lazy.map { |column| record.public_send(column) }.find(&:present?) : model.where(id: record.id).pick(ended_sql)
      value&.to_date
    end

    # The records in scope that ended on or before date.
    def ended_by(scope, date)
      bound = ended_date? ? date : date.in_time_zone.end_of_day
      scope.where(Arel::Nodes::LessThanOrEqual.new(ended_sql, Arel::Nodes.build_quoted(bound)))
    end

    def archived(scope = model.all)
      @archived ? @archived.call(scope) : scope.where.not(archived_at: nil)
    end

    def unarchived(scope = model.all)
      scope.where.not(id: archived(model.all).select(:id))
    end

    def archived?(record)
      archived(model.where(id: record.id)).exists?
    end

    def archive!(record)
      @archive ? @archive.call(record) : record.update!(archived_at: Time.current)
    end

    def restore!(record)
      @restore ? @restore.call(record) : record.update!(archived_at: nil)
    end

    def used_by(record)
      return Array(@used_by.call(record)) if @used_by
      return [] unless record.respond_to?(:checklists_using_this)

      record.checklists_using_this.where.not(status: :archived).pluck(:title)
    end

    def permitted?(user, record, action)
      return @permitted.call(user, record, action) if @permitted

      policy = Pundit.policy!(user, record)
      action == :copy ? policy.update? && Pundit.policy!(user, record.dup).create? : policy.update?
    end

    # Unarchived records due to be archived automatically.
    def due(today = Date.current)
      cutoff = auto_archive_cutoff(today)
      return model.none if cutoff.nil?

      scope = unarchived
      ended_by(@auto_scope ? @auto_scope.call(scope) : scope, cutoff)
    end

    def due?(record, today = Date.current)
      cutoff = auto_archive_cutoff(today)
      return false if cutoff.nil? || archived?(record)
      return false if @auto_scope && !@auto_scope.call(model.where(id: record.id)).exists?

      (ended = ended_on(record)) ? ended <= cutoff : false
    end

    private

    # ended_on as an Arel node.
    def ended_sql
      return Arel::Nodes::Grouping.new(Arel.sql(@ended_on)) if @ended_on.is_a?(String)

      columns = Array(@ended_on).map { |column| model.arel_table[column] }
      columns.one? ? columns.first : Arel::Nodes::NamedFunction.new("COALESCE", columns)
    end

    def ended_date?
      return @ended_type == :date if @ended_on.is_a?(String)

      Array(@ended_on).all? { |column| model.columns_hash[column.to_s]&.type == :date }
    end
  end
end
