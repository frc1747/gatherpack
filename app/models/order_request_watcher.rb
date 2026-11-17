# Someone following a request ("Following" on screen) besides its requester.
class OrderRequestWatcher < ApplicationRecord
  has_neat_id :ordw
  include CanBeHooked
  has_paper_trail versions: { class_name: "AuditLog" }

  belongs_to :order_request
  belongs_to :person

  validates :person_id, uniqueness: { scope: :order_request_id, message: "is already following" }

  def identifier_name
    "#{order_request&.display_title}: #{person&.display_name}"
  end
end
