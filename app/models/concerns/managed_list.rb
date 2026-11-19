# A row in a managed list: one of the things a group names for itself, such as
# a unit, a type or a condition. The table needs these columns:
#
#   t.string  :name, null: false
#   t.string  :plural
#   t.string  :key
#   t.integer :position, null: false, default: 0
#   t.boolean :active, null: false, default: true
#
# Records point at a row by id, so renaming it renames it everywhere. Rows in
# use can't be deleted, only retired (hidden from pickers but still shown on
# old records) or merged into another row. A row with a key is one that code
# looks up (`find_by!(key: "each")`); it can be renamed and retired but not
# deleted or merged away.
#
# Declare what points at the list so it can tell when a row is in use:
#
#   class StockUnit < ApplicationRecord
#     include ManagedList
#     managed_list uses: { items: :stock_unit_id }
#   end
#
# Keys of `uses` are table names (:items) or class names ("Inventory::Item").
module ManagedList
  extend ActiveSupport::Concern

  included do
    has_paper_trail versions: { class_name: "AuditLog" } unless self < PaperTrail::Model::InstanceMethods

    scope :ordered, -> { order(:position, :name) }
    scope :active, -> { where(active: true) }
    scope :retired, -> { where(active: false) }

    before_validation :tidy_managed_list_fields
    validates :name, presence: true, uniqueness: { case_sensitive: false }
    validates :key, uniqueness: true, allow_nil: true
    before_create :place_last, unless: :position?
    before_destroy :ensure_removable
  end

  class_methods do
    def managed_list(uses: {})
      @managed_list_uses = uses
    end

    # [[ModelClass, :column], ...] for each table that points at this list.
    def managed_list_references
      (@managed_list_uses || {}).map do |owner, column|
        klass = owner.is_a?(Class) ? owner : (owner.is_a?(Symbol) ? owner.to_s.classify : owner).constantize
        [ klass, column.to_sym ]
      end
    end

    # Creates the starting rows, in order, only when the list is empty, so
    # it's safe to call from a migration and again from the seeds. Each row is
    # a name or a hash of attributes.
    def seed_defaults!(rows)
      return false if exists?

      transaction do
        rows.each_with_index do |row, index|
          attributes = row.is_a?(Hash) ? row : { name: row }
          create!({ position: index }.merge(attributes))
        end
      end
      true
    end
  end

  def plural_name
    plural.presence || name.to_s.pluralize
  end

  def retired?
    !active?
  end

  def retire!
    update!(active: false)
  end

  def restore!
    update!(active: true)
  end

  # { ModelClass => count } for each table that uses this row.
  def usage
    self.class.managed_list_references.each_with_object({}) do |(klass, column), counts|
      count = klass.where(column => id).count
      counts[klass] = (counts[klass] || 0) + count if count.positive?
    end
  end

  def in_use?
    self.class.managed_list_references.any? { |klass, column| klass.where(column => id).exists? }
  end

  def removable?
    key.blank? && !in_use?
  end

  # Moves the row one place up or down among the rows that are active (or
  # retired) like it. Positions are renumbered without new versions: order
  # isn't worth an audit entry per row.
  def move!(direction)
    rows = self.class.where(active: active).ordered.to_a
    index = rows.index(self) or return false
    target = direction.to_s == "up" ? index - 1 : index + 1
    return false if target.negative? || target >= rows.size

    rows[index], rows[target] = rows[target], rows[index]
    self.class.transaction do
      rows.each_with_index do |row, position|
        row.update_column(:position, position) unless row.position == position
      end
    end
    true
  end

  # Points everything that uses this row at `other`, then deletes this row.
  # Each record is saved (without validation) so its change is audited.
  def merge_into!(other)
    raise ArgumentError, "can only merge into another row of the same list" unless other.instance_of?(self.class) && other.id != id
    raise ArgumentError, "#{name} is built in and can't be merged away" if key.present?

    transaction do
      self.class.managed_list_references.each do |klass, column|
        klass.where(column => id).find_each { |record| record.update_attribute(column, other.id) }
      end
      destroy!
    end
  end

  private

  def tidy_managed_list_fields
    self.name = name.strip if name
    self.plural = plural.presence&.strip
    self.key = key.presence
  end

  def place_last
    self.position = (self.class.maximum(:position) || -1) + 1
  end

  def ensure_removable
    if key.present?
      errors.add(:base, "#{name} is built in and can't be deleted. Retire it instead.")
    elsif in_use?
      uses = usage.map { |klass, count| "#{count} #{klass.model_name.human.downcase.pluralize(count)}" }.to_sentence
      errors.add(:base, "#{name} is in use (#{uses}), so it can't be deleted. Retire it or merge it into another one.")
    end
    throw :abort if errors[:base].any?
  end
end
