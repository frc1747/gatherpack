module Housekeeping
  # One registered kind of record (Housekeeping.register). Options:
  #
  # - ended_on: a column (Symbol, a date or time) or ->(record) { date }. When
  #   the record ended or closed; nil when it hasn't.
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
  # - label: the plural shown on screens. Default: the model's.
  # - list_path: the route helper of its list page, for a link back.
  class Type
    attr_reader :model, :key, :label, :list_path, :copier

    def initialize(model, key: nil, label: nil, ended_on:, archived: nil, archive: nil, restore: nil, used_by: nil,
      permitted: nil, copy: nil, available: nil, auto_archive: true, list_path: nil)
      @model = model
      @key = (key || model.table_name).to_s
      @label = label || model.model_name.human.pluralize
      @ended_on = ended_on
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

    def ended_on(record)
      value = @ended_on.is_a?(Symbol) ? record.public_send(@ended_on) : @ended_on.call(record)
      value&.to_date
    end

    # The records in scope that ended on or before date.
    def ended_by(scope, date)
      if @ended_on.is_a?(Symbol)
        column = model.columns_hash[@ended_on.to_s]
        bound = column&.type == :date ? date : date.in_time_zone.end_of_day
        scope.where(@ended_on => ..bound)
      else
        scope.where(id: scope.select { |record| (ended = ended_on(record)) && ended <= date }.map(&:id))
      end
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

    # Unarchived records that ended more than auto_archive_days before today.
    def due(today = Date.current)
      days = auto_archive_days
      return model.none if days.nil?

      ended_by(unarchived, today - days.days - 1.day)
    end
  end
end
