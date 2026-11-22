# What a signed-in person has coming up and still owes, for the
# "My Sign-ups and Commitments" dashboard card (signups spec §7, phase 6),
# rendered by signups_summaries/_summary. With checklists on, the card is
# "My Sign-ups and Checklists" and its second half reads checklist items
# (checklists spec §11.4, §10.4): see #checklists.
#
# Sign-ups are the upcoming active ones the person takes, made, or that
# count for them (as on a sheet's My sign-ups), on sheets they may see.
# Placing someone from the roster doesn't count as making their sign-up.
# They're listed as the person's own places and the places they signed
# others up for, as on the sheet.
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

  # One checklist a person (or a ward) is covered by, with the items they
  # can still finish, as the viewer may see them.
  ChecklistEntry = Struct.new(:person, :checklist, :status, :open_items, keyword_init: true)

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

  def checklists_enabled?
    person.present? && GatherPack::Features.enabled?(:checklists)
  end

  def title
    checklists_enabled? ? "My Sign-ups and Checklists" : "My Sign-ups and Commitments"
  end

  def empty?
    signups.empty? && commitments.empty? && checklists.empty?
  end

  # The first `limit` upcoming sign-ups, soonest first.
  def signups
    all_signups.first(limit)
  end

  # The listed sign-ups the person takes or that count for them, and those
  # they signed up someone else for.
  def own_signups
    signups.reject { |signup| signed_up_for_other?(signup) }
  end

  def signups_for_others
    signups.select { |signup| signed_up_for_other?(signup) }
  end

  def more_signups?
    all_signups.size > limit
  end

  # Commitments still running (not ended before today), by start date.
  def commitments
    @commitments ||= if commitments_enabled?
      visible_commitments.filter_map do |commitment|
        progress = commitment.progress_seen_by(person)
        next unless progress

        Item.new(progress: progress, page_person: progress.members.include?(person) ? person : progress.person)
      end
    else
      []
    end
  end

  # With checklists on: each checklist covering the person or one of their
  # wards that has an item the viewer can see and that isn't done, as the
  # viewer may see it. Empty while checklists are off.
  def checklists
    @checklists ||= if checklists_enabled?
      [ person, *person.wards ].flat_map do |subject|
        Checklists.checklist_for(subject, viewer: person).filter_map do |checklist, status|
          open_items = status.explained.select { |entry| entry.full? && %w[ not_met pending ].include?(entry.status) }
          ChecklistEntry.new(person: subject, checklist: checklist, status: status, open_items: open_items) if open_items.any?
        end
      end
    else
      []
    end
  end

  private

  # The current commitments the person's own commitments page shows them:
  # PersonCommitmentsPolicy#visible_commitments for the person themselves
  # (keep the two in step), less the ended ones. Ended commitments are left
  # out in the query, before the per-commitment checks, so years of past
  # seasons cost nothing.
  def visible_commitments
    Commitment.where(ends_on: Date.current..).includes(:team, :owing_team).order(:starts_on, :title).to_a
      .select { |commitment| commitment.covers?(person) || commitment.group_relative?(person) }
      .reject { |commitment| shown_as_checklist_item?(commitment) }
  end

  # A count item's commitment is listed with its checklist instead.
  def shown_as_checklist_item?(commitment)
    checklists_enabled? && commitment.respond_to?(:checklist_item) && commitment.checklist_item.present?
  end

  def all_signups
    @all_signups ||= if signups_enabled?
      # An event with no end time (dates added with only a start) is upcoming
      # until it starts.
      signups = Signup.active.joins(signup_slot: :event).where("COALESCE(events.end_time, events.start_time) >= ?", Time.current)
      signups.where(person_id: person.id).or(signups.where(on_behalf_of_id: person.id))
        .or(signups.where(signed_up_by_id: person.id, placed_by_organizer: false))
        .includes(:person, :on_behalf_of, signup_slot: [ :event, { signup_position: :signup_sheet } ])
        .to_a
        .select { |signup| sheet_visible?(signup.signup_sheet) }
        .sort_by { |signup| [ signup.event.start_time, signup.signup_sheet.title, signup.signup_position.position ] }
    else
      []
    end
  end

  def signed_up_for_other?(signup)
    signup.person_id != person.id && signup.signed_up_by_id == person.id
  end

  def sheet_visible?(sheet)
    @sheet_visible ||= {}
    @sheet_visible.fetch(sheet.id) { @sheet_visible[sheet.id] = SignupSheetPolicy.new(user, sheet).show? }
  end
end
