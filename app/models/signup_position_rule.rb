# A test a person must pass to take a position. Rules apply to whoever takes
# the place, not the signer. Adding a kind means a kind, its settings, a
# check, and a reason message.
#
# - badge: holds any of the badges
# - age: age on the event's date is within min_age and max_age; no birthday
#   on file fails
# - team: is a member of any of the teams or a team below one
# - checklist: finishes the checklist (Checklists::SignupRule, added by the
#   checklists connector)
#
# A position has at most one rule of each kind; a person must pass every
# rule, and within a badge or team rule any one listed is enough.
#
# Organizers see pass or fail on rules, never the data behind them. An
# organizer picks a sheet's dates and ages, so an age result would give
# away a birthday: see .age_visible_to? and #check_for.
class SignupPositionRule < ApplicationRecord
  has_neat_id :suru
  include CanBeHooked
  has_paper_trail versions: { class_name: "AuditLog" }

  belongs_to :signup_position

  enum :kind, { badge: 0, age: 1, team: 2, checklist: 3 }, validate: true

  normalizes :badge_ids, :team_ids, with: ->(ids) { Array(ids).compact_blank.uniq }

  validates :kind, uniqueness: { scope: :signup_position_id, message: ->(rule, _) { "This position already has #{rule.kind == "age" ? "an" : "a"} #{rule.kind} rule; change it instead" } }
  validates :badge_ids, presence: { message: "needs at least one badge" }, if: :badge?
  validates :team_ids, presence: { message: "needs at least one team" }, if: :team?
  validates :min_age, :max_age, numericality: { only_integer: true, greater_than_or_equal_to: 0 }, allow_nil: true
  validate :age_range, if: :age?

  # Shown instead of an age rule's reason to someone who may not see it.
  AGE_HIDDEN_REASON = "Doesn't meet this place's age rule".freeze
  # Shown to an organizer for an age rule that wasn't checked.
  AGE_NOT_CHECKED = "Age not checked".freeze
  # An organizer's own family through a relationship type members can add
  # themselves: the rule isn't checked, but this organizer can't place them
  # either, whatever their age.
  AGE_FAMILY_REASON = "Another organizer needs to place your family where there's an age rule".freeze

  before_validation :clear_other_settings

  delegate :signup_sheet, to: :signup_position

  def identifier_name
    "#{signup_position&.name}: #{description}"
  end

  def badges
    Badge.where(id: badge_ids)
  end

  def teams
    Team.where(id: team_ids)
  end

  # "Needs the Alcohol License badge", "Age 14 to 17", "In Concessions or Grill"
  def description
    case kind
    when "badge" then badge_requirement
    when "age" then "Age #{age_range_text}"
    when "team" then team_names.present? ? "In #{team_names}" : "In a team that no longer exists"
    end
  end

  # Whether the viewer may see if the person passes age rules, and why
  # not: the person themselves, an admin, or someone who manages them.
  # Installs with stricter birthday privacy can tighten this.
  def self.age_visible_to?(viewer, person)
    return false if viewer.nil? || person.nil?

    viewer.id == person.id || viewer.can_manage(person)
  end

  # Nil if the person passes, or why they don't, as the viewer may see it
  # (Signups::AgeCheck#mode_for). An age rule isn't checked at all for an
  # organizer of the sheet who may not see the person's result
  # (#unchecked_for?), so they can place them and nothing flags it. Anyone
  # else who may not see it (a parent signing up their child, or an
  # organizer placing family related through a trusted type, who still
  # can't place them against a rule) gets AGE_HIDDEN_REASON. An organizer's
  # family through any other type gets AGE_FAMILY_REASON whatever their
  # age: no approving your own family (decision 14), without telling the
  # organizer anything. Pass age_check to reuse one across rules and rows.
  def check_for(person, event, viewer, age_check: nil)
    return check(person, event) unless age?

    case (age_check || Signups::AgeCheck.new(signup_sheet, viewer)).mode_for(person)
    when :shown then check(person, event)
    when :unchecked then nil
    when :family then AGE_FAMILY_REASON
    else AGE_HIDDEN_REASON if check(person, event)
    end
  end

  # Whether this is an age rule #check_for skips for this viewer.
  def unchecked_for?(person, viewer, age_check: nil)
    age? && (age_check || Signups::AgeCheck.new(signup_sheet, viewer)).mode_for(person) == :unchecked
  end

  # Nil if the person passes, or why they don't, with the details. For
  # anything a viewer sees, use #check_for.
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

  # Deleted teams are left out; if none is left, nobody passes.
  def check_team(person)
    team_ids = teams.flat_map { |team| [ team.id ] + team.all_descendant_ids }
    return if team_ids.any? && Membership.where(person_id: person.id, team_id: team_ids).exists?

    team_names.present? ? "Must be in #{team_names}" : "Must be in a team that no longer exists"
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
    either_of(badges)
  end

  def team_names
    either_of(teams)
  end

  def either_of(records)
    records.order(:name).pluck(:name).to_sentence(two_words_connector: " or ", last_word_connector: ", or ")
  end

  def clear_other_settings
    self.badge_ids = [] unless badge?
    self.min_age = self.max_age = nil unless age?
    self.team_ids = [] unless team?
  end

  def age_range
    if min_age.nil? && max_age.nil?
      errors.add(:base, "Set a minimum age, a maximum age, or both")
    elsif min_age && max_age && min_age > max_age
      errors.add(:max_age, "can't be less than the minimum age")
    end
  end
end
