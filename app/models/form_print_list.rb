# A printable list of people with one form's answers. Who is on the list
# (a FormPopulation) and what's shown for them can come from different
# forms: the columns are this form's answers and chosen profile details.
# Nobody is silently left out: people who haven't answered, and people
# whose answers the viewer can't see, are listed or counted separately.
class FormPrintList
  Line = Struct.new(:person, :row, keyword_init: true)

  attr_reader :form, :viewer, :source, :questions, :fields

  def initialize(form:, viewer:, source:, questions: [], fields: [])
    @form = form
    @viewer = viewer
    @source = source
    @questions = questions
    @fields = fields
  end

  def population
    source.people
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
