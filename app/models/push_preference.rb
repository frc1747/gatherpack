# Which topics someone wants on their phones. No row means they haven't chosen,
# and each topic's default applies.
class PushPreference < ApplicationRecord
  has_neat_id :ppref

  belongs_to :user

  validates :user_id, uniqueness: true
end
