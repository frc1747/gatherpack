# The forms attached to one event, read for one viewer: who said they're
# coming (intent) and how that compares with who checked in. Intent is a
# planning count only. A person counts as attending only when checked in,
# and nothing here creates, changes, or reads anything but check-ins for
# attendance.
#
# Every count and list covers only people whose intent answer the viewer
# can read on the form (FormReport), so a leader sees their own people.
class EventForms
  attr_reader :event, :viewer

  def initialize(event, viewer:)
    @event = event
    @viewer = viewer
  end

  # Attached forms past draft, which members could have seen.
  def forms
    @forms ||= Form.where(event: event).where.not(status: %i[ draft archived ]).includes(:form_questions).order(:title).to_a
  end

  # The form that asks "Are you coming?", if one is attached.
  def intent_form
    @intent_form ||= forms.detect(&:intent_question)
  end

  def intent_question
    intent_form&.intent_question
  end

  def intent_report
    @intent_report ||= intent_form && FormReport.new(intent_form, viewer: viewer)
  end

  # Rows (people asked, or with a response) whose intent the viewer can read.
  def intent_rows
    @intent_rows ||= intent_report ? intent_report.rows.select { |row| intent_report.readable?(row, intent_question) } : []
  end

  def intent_of(row)
    intent_report.answer(row, intent_question)
  end

  # { "Yes" => n, "Maybe" => n, "No" => n, nil => no answer }
  def intent_counts
    counts = FormQuestion::INTENT_CHOICES.index_with { 0 }
    counts[nil] = 0
    intent_rows.each { |row| counts[intent_of(row)] = counts.fetch(intent_of(row), 0) + 1 }
    counts
  end

  # People who said yes, by their active (submitted) answer.
  def expected_people
    intent_rows.select { |row| intent_of(row) == "Yes" }.map(&:person)
  end

  def checked_in_ids
    @checked_in_ids ||= event.checkins.pluck(:person_id).to_set
  end

  def checked_in_count
    checked_in_ids.size
  end

  def checked_in_people
    Person.where(id: checked_in_ids.to_a).order(:last_name, :first_name).to_a
  end

  # Said yes but haven't checked in.
  def yes_not_checked_in
    expected_people.reject { |person| checked_in_ids.include?(person.id) }
  end

  # Checked in without saying yes, among people whose intent the viewer can read.
  def checked_in_without_yes
    intent_rows.select { |row| checked_in_ids.include?(row.person.id) && intent_of(row) != "Yes" }.map(&:person)
  end
end
