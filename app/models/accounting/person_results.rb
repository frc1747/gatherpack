# Person#accounting_result(key): a person's result for a rule, for Reports
# and widgets (which, like all architect code, see every result).
module Accounting::PersonResults
  extend ActiveSupport::Concern

  included do
    has_many :accounting_rule_results, dependent: :delete_all
  end

  def accounting_result(key)
    accounting_rule_results.joins(:rule).find_by(accounting_rules: { key: key.to_s })
  end
end
