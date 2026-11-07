module HousekeepingHelper
  # "more than 12 months ago" or "on or before 1 June 2026", for an
  # "ended before" filter (a Checklists::RelativeDate).
  def housekeeping_older_text(older)
    older.relative? ? "more than #{pluralize(older.amount, older.unit.singularize)} ago" : "on or before #{l(older.date, format: :long)}"
  end

  # Hidden fields carrying a nested param (a list's Ransack q) through
  # another form.
  def housekeeping_hidden_params(name, value)
    case value
    when Hash
      safe_join(value.map { |key, inner| housekeeping_hidden_params("#{name}[#{key}]", inner) })
    when Array
      safe_join(value.map { |inner| housekeeping_hidden_params("#{name}[]", inner) })
    when nil
      nil
    else
      hidden_field_tag(name, value, id: nil)
    end
  end
end
