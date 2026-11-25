# A person an admin said a customer isn't for ("Not this person", or an
# Unlink): never suggested or linked automatically for that customer again.
# Linking the two by hand removes it.
class AccountingCustomerDismissal < ApplicationRecord
  has_neat_id :acdm

  belongs_to :gateway
  belongs_to :person

  validates :customer_external_id, presence: true
  validates :person_id, uniqueness: { scope: %i[ gateway_id customer_external_id ] }
end
