# How each rule kind turns a person's matching records into a result. Each
# kind's #evaluate returns an Outcome: value (one of AccountingRule::VALUES
# for the kind, or what custom code returned), amount_cents and details.
module Accounting::Kinds
  Outcome = Struct.new(:value, :amount_cents, :details, keyword_init: true) do
    # details as they read back from the database (string keys, ISO dates),
    # so a fresh outcome compares equal to a saved result.
    def stored_details
      JSON.parse((details || {}).to_json)
    end
  end

  def self.for(kind)
    case kind.to_s
    when "balance" then Balance
    when "amount" then Amount
    when "count" then Count
    when "custom" then Custom
    else raise ArgumentError, "Unknown rule kind #{kind.inspect}"
    end
  end

  # Evaluates one person for one rule. records: an Accounting::RuleRecords.
  class Base
    attr_reader :rule, :person, :records, :today

    def initialize(rule, person, records:, today: Date.current)
      @rule = rule
      @person = person
      @records = records
      @today = today
    end

    def evaluate = raise NotImplementedError

    private
      def filter
        records.filter
      end

      def person_records
        @person_records ||= records.records_for(person)
      end

      def with_roles(roles)
        person_records.where(role: filter.roles(roles))
      end

      def outcome(value, amount_cents, details = {})
        Outcome.new(value: value, amount_cents: amount_cents, details: details)
      end
  end
end
