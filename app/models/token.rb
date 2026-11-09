class Token < ApplicationRecord
  has_neat_id :tok
  include CanBeHooked
  has_paper_trail versions: { class_name: "AuditLog" }
  belongs_to :tokenable, polymorphic: true, optional: true
  # Normalised before validating, so a card can't be added twice by entering
  # it in each reader's format. A unique index backs this up. Only a new
  # value is normalised: a stored one already is, and normalising it again
  # could change it.
  before_validation :rfidify_value, if: :will_save_change_to_value?
  validates :value, uniqueness: true

  class << self
    # we have 2 different kinds of RFID readers that return the information on the cards in different formats...
    def rfidify(rfid)
      if rfid.to_s.match?(/\A5700[0-9a-fA-F]+\z/)
        rfid.to_s[4..-1].to_i(16).to_s
      else
        rfid
      end
    end

    def find_by_rfid(rfid)
      find_by(value: rfidify(rfid))
    end
  end

  def pretty_value
    "[#{value.to_s.last(8)}]"
  end

  def identifier_name
    "#{tokenable&.identifier_name || '***'} - #{pretty_value}"
  end

  def identifier_icon
    "id-badge"
  end

  def self.ransackable_attributes(auth_object = nil)
    [ "created_at", "id", "tokenable_id", "tokenable_type", "updated_at", "value" ]
  end

  def self.ransackable_associations(auth_object = nil)
    [ "tokenable" ]
  end

  private

  def rfidify_value
    self.value = Token.rfidify(value)
  end
end
