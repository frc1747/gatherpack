# A rule's filters (AccountingRule#filters) as conditions on
# AccountingRecord's neutral columns, all combined with AND:
#   items, classes, locations: any of these ids (the arrays overlap)
#   txn_date_from, txn_date_to: the transaction date, inclusive
#   due_date_from, due_date_to: a charge's due date, inclusive
#   min_total: skip records whose total is below it, in cents
# roles narrows which roles a kind uses; the kind applies it (#roles).
class Accounting::RecordFilter
  OVERLAPS = {
    item_ids: "accounting_records.item_ids && ARRAY[?]::varchar[]",
    class_ids: "accounting_records.class_ids && ARRAY[?]::varchar[]",
    location_ids: "accounting_records.location_ids && ARRAY[?]::varchar[]"
  }.freeze

  attr_reader :filters

  def initialize(filters)
    @filters = (filters || {}).to_h.stringify_keys
  end

  def items
    Array(filters["items"])
  end

  # The kind's roles, narrowed to the filter's when it names any.
  def roles(kind_roles)
    chosen = Array(filters["roles"])
    chosen.empty? ? kind_roles : kind_roles & chosen
  end

  # items: false leaves the item filter out, for records whose lines aren't
  # what a rule's items name (payments, matched to charges instead).
  def apply(scope, items: true)
    scope = overlap(scope, :item_ids, self.items) if items
    scope = overlap(scope, :class_ids, Array(filters["classes"]))
    scope = overlap(scope, :location_ids, Array(filters["locations"]))
    scope = scope.where(txn_date: range("txn_date")) if range("txn_date")
    scope = due_dates(scope)
    scope = scope.where(total_cents: filters["min_total"].to_i..) if filters["min_total"].present?
    scope
  end

  # The amount of a record's lines whose item is one of the filter's.
  def line_cents(record)
    Array(record.lines).sum { |line| items.include?(line["item_id"].to_s) ? line["amount_cents"].to_i : 0 }
  end

  private
    def overlap(scope, column, ids)
      return scope if ids.empty?

      scope.where(OVERLAPS.fetch(column), ids)
    end

    # Only charges have due dates; the bounds don't drop other records.
    def due_dates(scope)
      bounds = range("due_date")
      return scope unless bounds

      scope.where(due_on: bounds).or(scope.where.not(role: "charge"))
    end

    def range(prefix)
      from = date(filters["#{prefix}_from"])
      to = date(filters["#{prefix}_to"])
      return nil unless from || to

      from..to
    end

    def date(value)
      value.present? ? Date.iso8601(value.to_s) : nil
    rescue Date::Error
      nil
    end
end
