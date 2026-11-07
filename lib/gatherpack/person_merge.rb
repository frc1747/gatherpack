module GatherPack
  # Registry of every column that points at a person (or at a login), so a
  # merge can move them all, and so "does this person have anything else"
  # has one answer. Each feature registers its own tables from a
  # `to_prepare` block:
  #
  #   GatherPack::PersonMerge.register(:widgets, :person_id, unique_by: %i[event_id])
  #
  # Options:
  #   type_column: polymorphic type column; only rows of the owner's type move.
  #   unique_by:   columns that, with this one, may appear once. A row of the
  #                person being merged away whose values the kept person
  #                already has is removed instead of moved.
  #   where:       conditions limiting which rows unique_by applies to.
  #   other_side:  a second person column on the same table (relationships).
  #                Rows already pointing at the kept person there are removed,
  #                since moving them would point both sides at one person.
  #   on_conflict: called with (removed_row, kept_row) before a duplicate is
  #                removed, to carry anything over (rows are column hashes).
  #   check:       called with (from_id, to_id); returns a warning for the
  #                preview (rows that move but clash), or nil.
  #   model:       ActiveRecord class used to remove rows, so their callbacks,
  #                dependents and audit entries run. Without it rows are
  #                deleted with SQL.
  #   action:      :move (default) or :delete (rows go with a removed login).
  #   owner:       :person (default) or :user, for columns pointing at logins.
  #
  # Columns that point at a person but must not move are listed with
  # `exempt`, so the coverage test knows they were considered.
  #
  # Registrations are kept until the app reloads its classes (see
  # config/initializers/person_merge.rb), so an initializer's load order
  # doesn't matter; registering the same column again replaces the entry.
  module PersonMerge
    OWNER_TYPES = { person: "Person", user: "User" }.freeze

    Entry = Struct.new(:table, :column, :type_column, :unique_by, :where, :other_side,
      :on_conflict, :check, :model, :action, :owner, :label, keyword_init: true) do
      def key
        [ owner, table, column ]
      end

      # SQL selecting this column's rows that point at owner_id.
      def rows_sql(owner_id, projection = Arel.star)
        arel = Arel::Table.new(table)
        query = arel.project(projection).where(arel[column].eq(owner_id))
        query = query.where(arel[type_column].eq(OWNER_TYPES.fetch(owner))) if type_column
        query.to_sql
      end
    end

    @entries = {}
    @exemptions = {}

    class << self
      def register(table, column, type_column: nil, unique_by: [], where: nil, other_side: nil,
        on_conflict: nil, check: nil, model: nil, action: :move, owner: :person, label: nil)
        entry = Entry.new(
          table: table.to_s, column: column.to_s, type_column: type_column&.to_s,
          unique_by: Array(unique_by).map(&:to_s), where: where, other_side: other_side&.to_s,
          on_conflict: on_conflict, check: check, model: model, action: action, owner: owner,
          label: label || table.to_s.humanize
        )
        @entries[entry.key] = entry
      end

      def unregister(table, column, owner: :person)
        @entries.delete([ owner, table.to_s, column.to_s ])
      end

      def exempt(table, column, reason:, owner: :person)
        @exemptions[[ owner, table.to_s, column.to_s ]] = reason
      end

      def entries(owner = nil)
        all = @entries.values
        owner ? all.select { |e| e.owner == owner } : all
      end

      def exemptions
        @exemptions.dup
      end

      def covers?(table, column, owner: :person)
        key = [ owner, table.to_s, column.to_s ]
        @entries.key?(key) || @exemptions.key?(key)
      end

      # Counts of the rows pointing at a person (and at their login, unless
      # include_login is false), by entry, leaving out entries with none and
      # tables named in except.
      def rows_for(person, except: [], include_login: true)
        except = Array(except).map(&:to_s)
        owners = { person: person.id }
        owners[:user] = person.user_id if include_login && person.user_id
        owners.flat_map do |owner, id|
          entries(owner).reject { |e| except.include?(e.table) }.filter_map do |entry|
            count = connection.select_value(entry.rows_sql(id, Arel.star.count)).to_i
            [ entry, count ] if count.positive?
          end
        end.to_h
      end

      # Whether anything registered points at the person, besides tables
      # named in except. A person with nothing else can be deleted outright.
      def references?(person, except: [], include_login: true)
        rows_for(person, except: except, include_login: include_login).any?
      end

      def reset!
        @entries = {}
        @exemptions = {}
      end

      private

      def connection
        ActiveRecord::Base.connection
      end
    end
  end
end
