class Widget < ApplicationRecord
  has_neat_id :wdg
  include CanBeHooked
  has_paper_trail versions: { class_name: "AuditLog" }
  belongs_to :team, optional: true

  VIEWER_LEVELS = %w[ user team manager admin ]
  PLACEMENTS = %w[ top left right ]
  STYLE_MODES = %w[ theme replace ]
  MIN_REFRESH_SECONDS = 15

  scope :enabled, -> { where(enabled: true) }
  scope :in_order, -> { order(:position, :title) }

  validates :title, presence: true
  validates :viewer, inclusion: { in: VIEWER_LEVELS }
  validates :placement, inclusion: { in: PLACEMENTS }
  validates :style_mode, inclusion: { in: STYLE_MODES }
  validates :position, numericality: { only_integer: true }
  validates :refresh_seconds, numericality: { only_integer: true, greater_than_or_equal_to: 0 }
  validate :refresh_is_off_or_long_enough
  validate :team_present_for_team_levels

  def self.ransackable_attributes(auth_object = nil)
    [ "title", "placement", "enabled", "updated_at" ]
  end

  def self.ransackable_associations(auth_object = nil)
    [ "team" ]
  end

  def identifier_icon
    "table-cells-large"
  end

  # Whether a person can see this widget on their dashboard. Admins see every
  # widget. Disabled widgets are hidden from everyone there; admins can still
  # preview them.
  def visible_to?(user)
    return false unless user.present?
    return true if user.admin
    return false unless enabled

    person = user.person
    case viewer
    when "user" then true
    when "team" then team.present? && person.present? && person.all_teams.include?(team)
    when "manager" then team.present? && person.present? && team.manager?(person)
    else false
    end
  end

  private

  def refresh_is_off_or_long_enough
    return if refresh_seconds.to_i.zero? || refresh_seconds.to_i >= MIN_REFRESH_SECONDS
    errors.add(:refresh_seconds, "must be 0 (off) or at least #{MIN_REFRESH_SECONDS}")
  end

  def team_present_for_team_levels
    errors.add(:team, "is required when only a team or its managers can see the widget") if %w[ team manager ].include?(viewer) && team.nil?
  end
end
