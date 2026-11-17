class Announcement < ApplicationRecord
  has_neat_id :ann
  include CanBeHooked
  has_paper_trail versions: { class_name: "AuditLog" }
  belongs_to :team, optional: true

  attr_accessor :notify_now

  validates :title, presence: true
  validates :content, presence: true
  validates :start_time, presence: true
  validates :end_time, presence: true

  scope :visible, -> { where("start_time < ? AND end_time > ?", DateTime.current, DateTime.current) }

  # The content as a reader sees it: markdown link targets and HTML tags
  # (with their attributes) removed, so searching only matches visible text.
  ransacker :visible_text do
    Arel.sql(<<~SQL.squish)
      regexp_replace(
        regexp_replace(announcements.content, '\\[([^\\]]*)\\]\\([^)]*\\)', '\\1', 'g'),
        '<[^>]*>', '', 'g')
    SQL
  end

  def self.ransackable_attributes(auth_object = nil)
    [ "title", "content", "visible_text", "start_time", "end_time", "team_id", "updated_at" ]
  end

  def self.ransackable_associations(auth_objects = nil)
    [ "team" ]
  end

  def identifier_icon
    "comment"
  end
end
