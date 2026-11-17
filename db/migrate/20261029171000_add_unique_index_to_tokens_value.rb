# Each card value belongs to one card. Values were already stored in one
# format (see Token.rfidify), but the uniqueness check ran before that, so
# a card could be added twice. If two cards share a value, the migration
# stops and lists them: which card is right is for an admin to decide, not
# the migration.
class AddUniqueIndexToTokensValue < ActiveRecord::Migration[8.1]
  class MigrationToken < ActiveRecord::Base
    self.table_name = "tokens"
  end

  def up
    duplicates = MigrationToken.where(value: MigrationToken.group(:value).having("COUNT(*) > 1").select(:value))
      .order(:value, :created_at).group_by(&:value)
    if duplicates.any?
      list = duplicates.map { |value, tokens| "#{value}: tokens #{tokens.map(&:id).join(', ')}" }.join("\n")
      raise <<~MESSAGE
        These card values belong to more than one token. In a Rails console
        (bin/rails console), change or delete all but one token for each value,
        e.g. Token.find("<id>").destroy, then run the migration again:
        #{list}
      MESSAGE
    end

    add_index :tokens, :value, unique: true
  end

  def down
    remove_index :tokens, :value
  end
end
