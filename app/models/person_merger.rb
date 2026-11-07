# Merges two people into one: every row registered with
# GatherPack::PersonMerge moves from the person being merged away (drop) to
# the one being kept (keep), duplicates are removed, keep's blank profile
# fields are filled from drop, and drop is deleted. One audit entry on the
# kept person records what moved.
class PersonMerger
  include ActiveModel::Model
  include ActiveModel::Attributes

  # Profile columns that are never copied from the person merged away.
  SKIPPED_FIELDS = %w[id user_id created_at updated_at].freeze

  # What happens to one registered column: rows that move, and rows that are
  # removed because keep already has them (or they point at keep already).
  Change = Struct.new(:entry, :moving, :removing, keyword_init: true) do
    def label
      entry.label
    end

    def delete?
      entry.action == :delete
    end

    def any?
      moving.any? || removing.any?
    end
  end

  attribute :keep_nid, :string
  attribute :drop_nid, :string
  # Whose login stays when both people have one: "keep" or "drop".
  attribute :keep_login, :string

  validate :people_chosen
  validate :login_chosen
  validate :removed_login_is_not_privileged

  def keep
    @keep ||= find_person(keep_nid)
  end

  def drop
    @drop ||= find_person(drop_nid)
  end

  def both_have_logins?
    keep&.user.present? && drop&.user.present?
  end

  # The login the merged person ends up with.
  # Memoized, since the merge repoints people.user_id.
  def kept_login
    return @kept_login if defined?(@kept_login)
    @kept_login = if both_have_logins?
      keep_login == "drop" ? drop.user : keep.user
    else
      keep&.user || drop&.user
    end
  end

  # The login deleted by the merge, if both people have one.
  def removed_login
    return @removed_login if defined?(@removed_login)
    @removed_login = if both_have_logins?
      keep_login == "drop" ? keep.user : drop.user
    end
  end

  # Changes for the people's rows, in registry order, with logins last.
  def changes
    @changes ||= person_changes + login_changes
  end

  # Blank profile fields on keep that drop has a value for.
  def filled_fields
    @filled_fields ||= (Person.column_names - SKIPPED_FIELDS).each_with_object({}) do |field, filled|
      filled[field] = drop[field] if keep[field].blank? && drop[field].present?
    end
  end

  # Runs the merge as actor (a User). Returns false, with errors, if refused.
  def merge(actor:)
    return false unless valid?

    AuditLog.transaction do
      ActiveRecord::Base.transaction do
        summary = {}
        kept_login
        removed_login
        changes.each { |change| apply(change, summary) }
        move_login(summary)
        fill_profile(summary)

        summary["merged_person"] = [ "#{drop.display_name} (#{drop.id})", nil ]
        dropped = Person.find(drop.id)
        dropped.destroy!
        removed_login&.reload&.destroy!

        AuditLog.create!(
          item_type: "Person", item_id: keep.id, event: "merge", whodunnit: actor.id,
          object_changes: PaperTrail.serializer.dump(summary), created_at: Time.current
        )
      end
    end
    keep.reload
    true
  end

  private

  def find_person(value)
    return if value.blank?
    Person.find_by_neat_id(value) || Person.find_by(id: value)
  end

  def people_chosen
    errors.add(:keep_nid, "must be chosen") if keep.nil?
    errors.add(:drop_nid, "must be chosen") if drop.nil?
    errors.add(:base, "Choose two different people") if keep && keep == drop
  end

  def login_chosen
    return unless both_have_logins?
    return if %w[keep drop].include?(keep_login)
    errors.add(:keep_login, "must be chosen: both people have a login and only one can stay")
  end

  def removed_login_is_not_privileged
    login = removed_login if errors.empty?
    return unless login&.admin? || login&.architect?
    errors.add(:keep_login, "can't remove #{login.email}: it has admin access. Keep that login, or remove its admin access first")
  end

  def person_changes
    GatherPack::PersonMerge.entries(:person).map { |entry| plan(entry, drop.id, keep.id, Person.polymorphic_name) }
  end

  def login_changes
    return [] unless removed_login
    GatherPack::PersonMerge.entries(:user).map { |entry| plan(entry, removed_login.id, kept_login.id, User.polymorphic_name) }
  end

  # Sorts from's rows into moving and removing. A removed row is paired with
  # the row of to's that it duplicates (nil when it points at to already).
  def plan(entry, from, to, type)
    from_rows = rows(entry, from, type)
    return Change.new(entry: entry, moving: [], removing: from_rows.map { |row| [ row, nil ] }) if entry.action == :delete

    kept = entry.unique_by.any? ? rows(entry, to, type).select { |row| applies?(entry, row) } : []
    kept_by_key = kept.index_by { |row| row.values_at(*entry.unique_by) }

    moving = []
    removing = []
    from_rows.each do |row|
      if entry.other_side && row[entry.other_side] == to
        removing << [ row, nil ]
      elsif entry.unique_by.any? && applies?(entry, row) && (match = kept_by_key[row.values_at(*entry.unique_by)])
        removing << [ row, match ]
      else
        moving << row
      end
    end
    Change.new(entry: entry, moving: moving, removing: removing)
  end

  def rows(entry, owner_id, type)
    table = Arel::Table.new(entry.table)
    query = table.project(Arel.star).where(table[entry.column].eq(owner_id))
    query = query.where(table[entry.type_column].eq(type)) if entry.type_column
    connection.select_all(query.to_sql).to_a
  end

  def applies?(entry, row)
    (entry.where || {}).all? { |column, value| row[column.to_s].to_s == value.to_s }
  end

  def apply(change, summary)
    entry = change.entry
    to = entry.owner == :user ? kept_login.id : keep.id

    if change.removing.any?
      change.removing.each { |row, match| entry.on_conflict&.call(row, match) if match }
      ids = change.removing.map { |row, _| row["id"] }
      if entry.model
        entry.model.where(id: ids).find_each(&:destroy!)
      else
        execute("DELETE FROM #{quoted(entry.table)} WHERE id IN (?)", ids)
      end
      summary["#{entry.table}.#{entry.column} removed"] = [ ids.join(", "), nil ]
    end

    if change.moving.any?
      ids = change.moving.map { |row| row["id"] }
      execute("UPDATE #{quoted(entry.table)} SET #{connection.quote_column_name(entry.column)} = ? WHERE id IN (?)", to, ids)
      summary["#{entry.table}.#{entry.column} moved"] = [ ids.join(", "), to ]
    end
  end

  def move_login(summary)
    summary["removed_login"] = [ removed_login.email, nil ] if removed_login
    login = kept_login
    return if login.nil? || keep.user_id == login.id

    summary["user_id"] = [ keep.user_id, login.id ]
    drop.update_columns(user_id: nil) if drop.user_id == login.id
    keep.update_columns(user_id: login.id)
  end

  def fill_profile(summary)
    return if filled_fields.empty?
    filled_fields.each { |field, value| summary[field] = [ keep[field], value ] }
    keep.update_columns(filled_fields)
  end

  def execute(sql, *binds)
    connection.exec_update(ActiveRecord::Base.sanitize_sql_array([ sql, *binds ]))
  end

  def quoted(table)
    connection.quote_table_name(table)
  end

  def connection
    ActiveRecord::Base.connection
  end
end
