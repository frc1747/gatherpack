# Whoever manages the form manages its questions. A form run only by its
# creator (the creator badge) can't have signatures or questions linked to
# profile fields: consent and profile updates stay with leaders.
class FormQuestionPolicy < ApplicationPolicy
  %i[ index? show? destroy? move? ].each do |action|
    define_method(action) { form_policy.manage? }
  end

  def create?
    form_policy.manage? && (!form_policy.creator_only? || allowed_for_creator?)
  end

  def update?
    create?
  end

  def allowed_for_creator?
    !record.signature? && record.person_field_id.blank?
  end

  private

  def form_policy
    @form_policy ||= FormPolicy.new(user, record.form)
  end
end
