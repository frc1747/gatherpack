# An order or packing list: one form's active answers to chosen questions,
# for an event's people, with chosen profile details alongside. Based on
# who said they're coming (expected, for ordering ahead), who checked in
# (for handing out), or everyone the form asks. Nobody is silently left
# out: people with no answer on file, and people whose answers the viewer
# can't see, are listed or counted separately.
class FormOrderSheet
  BASES = %w[ expected checked_in asked ].freeze

  Line = Struct.new(:person, :row, keyword_init: true)

  attr_reader :form, :event, :viewer, :basis, :questions, :fields

  def initialize(form:, viewer:, event: nil, basis: "expected", questions: [], fields: [])
    @form = form
    @event = event
    @viewer = viewer
    @basis = BASES.include?(basis.to_s) ? basis.to_s : "expected"
    @basis = "asked" if event.nil?
    @questions = questions
    @fields = fields
  end

  def event_forms
    @event_forms ||= event && EventForms.new(event, viewer: viewer)
  end

  # Expected needs a form on the event that asks who's coming.
  def basis_available?
    basis != "expected" || event_forms&.intent_form.present?
  end

  def population
    @population ||= case basis
    when "expected" then basis_available? ? event_forms.expected_people : []
    when "checked_in" then event_forms.checked_in_people
    else report_for(nil).rows.select { |row| row.access.in_audience? }.map(&:person)
    end.sort_by { |person| [ person.last_name.to_s.downcase, person.first_name.to_s.downcase ] }
  end

  def report
    @report ||= report_for(population.map(&:id))
  end

  # People with an active answer the viewer can see.
  def listed
    split[:listed]
  end

  # People with nothing on file: no response, or nothing submitted.
  def no_choice
    split[:no_choice]
  end

  # People whose answers the viewer can't see.
  def hidden
    split[:hidden]
  end

  def answer(line, question)
    report.answer(line.row, question)
  end

  def profile(line, field)
    field_access(line.person).readable?(field) ? line.person.field_value(field) : nil
  end

  def profile_readable?(line, field)
    field_access(line.person).readable?(field)
  end

  # { choice => count } over the listed people. Multiple choice answers
  # count each choice.
  def tally(question)
    counts = question.value_type.type_boolean? ? { true => 0 } : question.value_type.choice_list.index_with { 0 }
    counts[nil] = 0
    listed.each do |line|
      value = report.readable?(line.row, question) ? answer(line, question) : nil
      Array(value.nil? ? [ nil ] : value).each { |choice| counts[choice] = counts.fetch(choice, 0) + 1 }
    end
    counts
  end

  private

  def report_for(only)
    FormReport.new(form, viewer: viewer, only: only)
  end

  def split
    @split ||= begin
      rows = report.rows.index_by { |row| row.person.id }
      reachable = form.reachable_subjects.where(id: population.map(&:id)).ids.to_set
      result = { listed: [], no_choice: [], hidden: [] }
      population.each do |person|
        row = rows[person.id]
        if row&.submission
          result[:listed] << Line.new(person: person, row: row)
        elsif row || !reachable.include?(person.id)
          result[:no_choice] << Line.new(person: person, row: row)
        else
          result[:hidden] << Line.new(person: person, row: nil)
        end
      end
      result
    end
  end

  def field_access(person)
    @field_access ||= {}
    @field_access[person.id] ||= PersonFieldAccess.new(viewer, person)
  end
end
