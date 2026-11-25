# Part conditions (inventory spec §3.15): a managed list that replaces the
# condition enum on tracked units, and the condition words in their
# history. needs_attention marks the conditions a unit can't be used in
# until it's repaired (asked about before installing); out_of_service marks
# the ones that take it out of every count. The defaults keep the enum's
# words as their keys, so code finds Needs repair, Good and Retired by key
# whatever they are called.
class CreateUnitConditions < ActiveRecord::Migration[8.1]
  class UnitCondition < ActiveRecord::Base
    self.table_name = "unit_conditions"
  end

  DEFAULTS = [
    { name: "New", key: "new" },
    { name: "Good", key: "good" },
    { name: "Worn", key: "worn" },
    { name: "Needs repair", key: "needs_repair", needs_attention: true },
    { name: "Broken", key: "broken", needs_attention: true },
    { name: "Retired", key: "retired", out_of_service: true }
  ].freeze

  def change
    create_table :unit_conditions, id: :uuid do |t|
      t.string :name, null: false
      t.string :plural
      t.string :key
      t.integer :position, null: false, default: 0
      t.boolean :active, null: false, default: true
      t.boolean :needs_attention, null: false, default: false
      t.boolean :out_of_service, null: false, default: false
      t.timestamps
    end
    add_index :unit_conditions, "lower(name)", unique: true
    add_index :unit_conditions, :key, unique: true
    add_reference :item_units, :unit_condition, type: :uuid, foreign_key: true
    add_reference :item_unit_events, :condition_before, type: :uuid, foreign_key: { to_table: :unit_conditions }
    add_reference :item_unit_events, :condition_after, type: :uuid, foreign_key: { to_table: :unit_conditions }

    reversible do |dir|
      dir.up { self.class.convert_up }
      dir.down { self.class.convert_down }
    end

    change_column_null :item_units, :unit_condition_id, false
    remove_column :item_units, :condition, :string, null: false, default: "new"
    remove_column :item_unit_events, :condition_before, :string
    remove_column :item_unit_events, :condition_after, :string
  end

  def self.convert_up
    UnitCondition.reset_column_information
    seed_defaults
    words = connection.select_values(<<~SQL.squish)
      SELECT condition FROM item_units UNION SELECT condition_before FROM item_unit_events
      UNION SELECT condition_after FROM item_unit_events
    SQL
    words.compact.each do |word|
      row = condition_for(word)
      connection.execute(sanitize([ "UPDATE item_units SET unit_condition_id = ? WHERE condition = ?", row.id, word ]))
      connection.execute(sanitize([ "UPDATE item_unit_events SET condition_before_id = ? WHERE condition_before = ?", row.id, word ]))
      connection.execute(sanitize([ "UPDATE item_unit_events SET condition_after_id = ? WHERE condition_after = ?", row.id, word ]))
    end
  end

  # Each unit and history line gets back its row's key, or for a row added
  # since, the key of the default row with the same flags.
  def self.convert_down
    connection.add_column :item_units, :condition, :string, null: false, default: "new" unless connection.column_exists?(:item_units, :condition)
    %w[condition_before condition_after].each do |column|
      connection.add_column :item_unit_events, column, :string unless connection.column_exists?(:item_unit_events, column)
    end
    UnitCondition.reset_column_information
    UnitCondition.find_each do |row|
      word = row.key.presence || (row.out_of_service ? "retired" : (row.needs_attention ? "needs_repair" : "good"))
      connection.execute(sanitize([ "UPDATE item_units SET condition = ? WHERE unit_condition_id = ?", word, row.id ]))
      connection.execute(sanitize([ "UPDATE item_unit_events SET condition_before = ? WHERE condition_before_id = ?", word, row.id ]))
      connection.execute(sanitize([ "UPDATE item_unit_events SET condition_after = ? WHERE condition_after_id = ?", word, row.id ]))
    end
  end

  def self.seed_defaults
    return if UnitCondition.exists?

    DEFAULTS.each_with_index { |row, index| UnitCondition.create!(row.merge(position: index)) }
  end

  # The row keyed as the word, or one named like it, or a new one.
  def self.condition_for(word)
    UnitCondition.find_by(key: word) ||
      UnitCondition.where("LOWER(name) = ?", word.humanize.downcase).first ||
      UnitCondition.create!(name: word.humanize, position: UnitCondition.maximum(:position).to_i + 1)
  end

  def self.connection
    ActiveRecord::Base.connection
  end

  def self.sanitize(sql)
    ActiveRecord::Base.sanitize_sql_array(sql)
  end
end
