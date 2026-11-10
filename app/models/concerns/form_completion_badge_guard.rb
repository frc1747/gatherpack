# A form's completion badge is given out by completing the form, and the
# people who run a form choose who it asks, so a completion badge can't also
# give access to people's information. Included in the badge grant models
# (FormBadgeGrant, and PersonFieldBadgeGrant from the forms initializer) so a
# completion badge can't be given access afterwards.
module FormCompletionBadgeGuard
  extend ActiveSupport::Concern

  included do
    validate :badge_isnt_a_completion_badge, if: -> { badge_id && will_save_change_to_badge_id? }
  end

  private

  def badge_isnt_a_completion_badge
    errors.add(:badge, "is a form's completion badge, so it can't give access") if Form.exists?(completion_badge_id: badge_id)
  end
end
