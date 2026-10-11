# A test a person must pass to take a position. Rules apply to whoever takes
# the place, not the signer. Adding a kind means a kind, its settings, a
# check, and a reason message.
#
# - badge: holds any of the badges
# - age: age on the event's date is within min_age and max_age; no birthday
#   on file fails
# - team: is a member of the team or a team below it
class SignupPositionRule < ApplicationRecord
  has_neat_id :suru
  include CanBeHooked
  has_paper_trail versions: { class_name: "AuditLog" }

  belongs_to :signup_position
  belongs_to :team, optional: true

  enum :kind, { badge: 0, age: 1, team: 2 }, validate: true

  normalizes :badge_ids, with: ->(ids) { Array(ids).compact_blank.uniq }

  validates :badge_ids, presence: { message: "needs at least one badge" }, if: :badge?
  validates :team, presence: true, if: :team?
  validates :min_age, :max_age, numericality: { only_integer: true, greater_than_or_equal_to: 0 }, allow_nil: true
  validate :age_range, if: :age?

  before_validation :clear_other_settings

  delegate :signup_sheet, to: :signup_position

  def identifier_name
    "#{signup_position&.name}: #{description}"
  end

  def badges
    Badge.where(id: badge_ids)
  end

  # "Needs the Alcohol License badge", "Age 14 to 17", "In Concessions"
  def description
    case kind
    when "badge" then badge_requirement
    when "age" then "Age #{age_range_text}"
    when "team" then "In #{team&.name}"
    end
  end

  # Nil if the person passes, or why they don't.
  def check(person, event)
    case kind
    when "badge" then check_badge(person)
    when "age" then check_age(person, event)
    when "team" then check_team(person)
    end
  end

  private

  # Deleted badges are left out; if none is left, nobody passes.
  def check_badge(person)
    return if BadgeAssignment.where(person_id: person.id, badge_id: badge_ids).exists?

    badge_requirement
  end

  def badge_requirement
    names = badge_names
    names.present? ? "Needs the #{names} badge" : "Needs a badge that no longer exists"
  end

  def check_age(person, event)
    return "Must be #{age_range_text} (no birthday on file)" if person.birthday.nil?

    date = event.start_time.in_time_zone.to_date
    age = age_on(person.birthday, date)
    return if (min_age.nil? || age >= min_age) && (max_age.nil? || age <= max_age)

    "Must be #{age_range_text} on #{date.strftime("%b %-d")}"
  end

  def check_team(person)
    return if Membership.where(person_id: person.id, team_id: [ team_id ] + team.all_descendant_ids).exists?

    "Must be in #{team.name}"
  end

  def age_on(birthday, date)
    date.year - birthday.year - (date.strftime("%m%d") < birthday.strftime("%m%d") ? 1 : 0)
  end

  def age_range_text
    if min_age && max_age then "#{min_age} to #{max_age}"
    elsif min_age then "#{min_age} or older"
    else "#{max_age} or younger"
    end
  end

  def badge_names
    badges.order(:name).pluck(:name).to_sentence(two_words_connector: " or ", last_word_connector: ", or ")
  end

  def clear_other_settings
    self.badge_ids = [] unless badge?
    self.min_age = self.max_age = nil unless age?
    self.team_id = nil unless team?
  end

  def age_range
    if min_age.nil? && max_age.nil?
      errors.add(:base, "Set a minimum age, a maximum age, or both")
    elsif min_age && max_age && min_age > max_age
      errors.add(:max_age, "can't be less than the minimum age")
    end
  end
end
