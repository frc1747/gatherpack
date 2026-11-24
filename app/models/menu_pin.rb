# A sidebar item a person pinned to the top of their menu. +path_key+ names
# the item: its path helper ("people_path"), "my_hours", or "page:<id>" for a
# report Page. Personal display state, so no hooks or audit trail.
class MenuPin < ApplicationRecord
  belongs_to :user

  validates :path_key, presence: true, length: { maximum: 255 }, uniqueness: { scope: :user_id }

  before_create { self.position = (MenuPin.where(user_id: user_id).maximum(:position) || 0) + 1 }

  def self.page_key(page)
    "page:#{page.id}"
  end
end
