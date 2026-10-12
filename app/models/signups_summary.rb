# What a signed-in person has coming up and still owes, for the
# "My sign-ups and commitments" dashboard widget (signups spec §7, phase 6):
#
#   <%= render "signups_summaries/summary" %>
#
# Sign-ups are the upcoming active ones the person takes, made, or that
# count for them (as on a sheet's My sign-ups), on sheets they may see.
# Commitments are those PersonCommitmentsPolicy shows them on their own
# commitments page: what they owe, and what a group they're related to
# through the commitment's relationship type owes (a parent's children),
# read through Commitment#progress_seen_by. Each half is empty while its
# feature is off, and the whole is empty for a user with no person.
class SignupsSummary
  DEFAULT_LIMIT = 5

  # A commitment's progress as the person sees it, and whose commitments
  # page to link to.
  Item = Struct.new(:progress, :page_person, keyword_init: true)

  attr_reader :user, :person, :limit

  def initialize(user, limit: DEFAULT_LIMIT)
    @user = user
    @person = user&.person
    @limit = limit
  end

  def signups_enabled?
    person.present? && GatherPack::Features.enabled?(:signups)
  end

  def commitments_enabled?
    person.present? && GatherPack::Features.enabled?(:commitments)
  end

  def empty?
    signups.empty? && commitments.empty?
  end

  # The first `limit` upcoming sign-ups, soonest first.
  def signups
    all_signups.first(limit)
  end

  def more_signups?
    all_signups.size > limit
  end

  # Commitments still running (not ended before today), by start date.
  def commitments
    @commitments ||= if commitments_enabled?
      PersonCommitmentsPolicy.new(user, person).visible_commitments
        .reject { |commitment| commitment.ends_on < Date.current }
        .filter_map do |commitment|
          progress = commitment.progress_seen_by(person)
          next unless progress

          Item.new(progress: progress, page_person: progress.members.include?(person) ? person : progress.person)
        end
    else
      []
    end
  end

  private

  def all_signups
    @all_signups ||= if signups_enabled?
      signups = Signup.active.joins(signup_slot: :event).where(events: { end_time: Time.current.. })
      signups.where(person_id: person.id).or(signups.where(signed_up_by_id: person.id)).or(signups.where(on_behalf_of_id: person.id))
        .includes(:person, :on_behalf_of, signup_slot: [ :event, { signup_position: :signup_sheet } ])
        .to_a
        .select { |signup| sheet_visible?(signup.signup_sheet) }
        .sort_by { |signup| [ signup.event.start_time, signup.signup_sheet.title, signup.signup_position.position ] }
    else
      []
    end
  end

  def sheet_visible?(sheet)
    @sheet_visible ||= {}
    @sheet_visible.fetch(sheet.id) { @sheet_visible[sheet.id] = SignupSheetPolicy.new(user, sheet).show? }
  end
end
