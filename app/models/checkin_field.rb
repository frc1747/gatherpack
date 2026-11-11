class CheckinField < ApplicationRecord
  has_neat_id :ckf
  has_paper_trail versions: { class_name: "AuditLog" }
  belongs_to :event_type
  # A field's answers go with it, each removed through its own callbacks so
  # the audit log keeps them. The delete confirmation says how many.
  has_many :checkin_field_responses, dependent: :destroy
  enum :permission, added_by_admin: 0, added_by_manager: 1, added_by_team_member: 2, added_by_participant: 3, added_by_user: 4

  validates :name, presence: true

  after_create :create_checkin_field_responses

  def self.ransackable_attributes(auth_object = nil)
    [ "name", "permission", "updated_at" ]
  end

  def identifier_name
    "#{event_type.name} / #{name}"
  end

  # Responses with an answer filled in (every check-in gets a blank one).
  def answer_count
    checkin_field_responses.where.not(response: [ nil, "" ]).count
  end

  private

  def create_checkin_field_responses
    event_type.events.where("start_time > ?", Time.current).each do |event|
      event.checkins.each do |checkin|
        checkin.refresh_fields
      end
    end
  end
end
