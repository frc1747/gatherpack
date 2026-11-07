# One line on a checklist (spec §5.2): a kind (Checklists.item_kind) with
# its config, a label and position, whether it counts toward the overall,
# optional dates overriding the checklist's window, a due date, who sees it
# and, inside an any_of group, its parent. Its rules narrow who it applies
# to; everyone else gets exempt with exempt_label.
class ChecklistItem < ApplicationRecord
  has_neat_id :chli
  include CanBeHooked
  has_paper_trail versions: { class_name: "AuditLog" }

  belongs_to :checklist, inverse_of: :checklist_items
  belongs_to :parent, class_name: "ChecklistItem", optional: true, inverse_of: :children
  has_many :children, -> { order(:position, :created_at) }, class_name: "ChecklistItem", foreign_key: :parent_id,
    inverse_of: :parent, dependent: :destroy
  has_many :checklist_rules, foreign_key: :item_id, inverse_of: :item, dependent: :destroy
  has_many :checklist_excuses, foreign_key: :item_id, inverse_of: :item, dependent: :destroy
  has_many :checklist_results, foreign_key: :item_id, inverse_of: :item, dependent: :delete_all

  validates :label, presence: true
  validates :kind, presence: true
  validates :read_level, inclusion: { in: Checklists::READ_LEVELS.keys }, allow_blank: true
  validates :starts_within_unit, inclusion: { in: Checklist::WITHIN_UNITS }, allow_blank: true
  validates :starts_within_amount, numericality: { only_integer: true, greater_than: 0 }, allow_nil: true
  validate :kind_registered, if: :kind_changed?
  validate :kind_config
  validate :parent_is_group
  validate :no_cycles

  before_validation :clear_unused_start
  before_create :place_last
  after_commit :refresh_checklist

  def identifier_name
    "#{checklist&.title}: #{label}"
  end

  def identifier_icon
    "square-check"
  end

  def kind_class
    Checklists.item_kind(kind)
  end

  def kind_label
    kind_class&.label || kind.to_s.humanize
  end

  # The read level that applies: its own, else the kind's default, else the
  # checklist's.
  def effective_read_level
    read_level.presence || kind_class&.default_read_level(self) || checklist.read_level
  end

  def config
    super || {}
  end

  # Sets config from form params through the kind, keeping only its fields.
  def config_params=(params)
    self.config = kind_class ? kind_class.normalize_config(params || {}) : {}
  end

  def describe
    kind_class ? kind_class.describe(self) : label
  end

  def container?
    kind_class&.container? || false
  end

  # Whole-item excuses in force on a date.
  def active_excuses(date = Date.current)
    checklist_excuses.whole_item.in_force(date)
  end

  # The checklists reachable from this checklist through checklist items,
  # including the one this item would require.
  def self.reachable_checklist_ids(start_ids)
    seen = Set.new
    queue = Array(start_ids).compact
    while (id = queue.shift)
      next if seen.include?(id)

      seen << id
      queue.concat(ChecklistItem.where(checklist_id: id, kind: "checklist").filter_map { |item| item.config["checklist_id"].presence })
    end
    seen
  end

  private

  def kind_registered
    errors.add(:kind, "isn't available") unless kind_class
  end

  def kind_config
    kind_class&.validate(self)
  end

  def parent_is_group
    return if parent.nil?

    errors.add(:parent, "must be a group on the same checklist") unless parent.container? && parent.checklist_id == checklist_id
    errors.add(:parent, "can't be the item itself") if parent_id.present? && parent_id == id
  end

  # A checklist that requires itself, directly or through others, never
  # settles; refuse the item that would close the loop.
  def no_cycles
    return unless kind == "checklist" && (target = config["checklist_id"].presence)
    return errors.add(:base, "A checklist can't require itself") if target == checklist_id

    if self.class.reachable_checklist_ids([ target ]).include?(checklist_id)
      errors.add(:base, "That checklist already requires this one, directly or through others")
    end
  end

  def clear_unused_start
    self.starts_on = nil if starts_within_amount.present?
    self.starts_within_unit = nil if starts_within_amount.blank?
  end

  def place_last
    return if position.to_i.positive?

    siblings = ChecklistItem.where(checklist_id: checklist_id, parent_id: parent_id)
    self.position = siblings.maximum(:position).to_i + 1
  end

  def refresh_checklist
    return unless Checklists.enabled?

    found = Checklist.find_by(id: checklist_id)
    Checklists.mark(found, :all) if found && !found.archived?
  end
end
