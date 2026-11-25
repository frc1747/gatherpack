# "Count": how many matching records the person has (receipts this year,
# say). Values: some, none.
class Accounting::Kinds::Count < Accounting::Kinds::Base
  ROLES = %w[ charge receipt payment credit refund ].freeze

  def evaluate
    count = filter.apply(with_roles(ROLES)).count
    outcome(count.positive? ? "some" : "none", nil, { count: count })
  end
end
