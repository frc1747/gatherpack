class FormQuestionPolicy < ApplicationPolicy
  %i[ index? show? create? update? destroy? move? ].each do |action|
    define_method(action) { FormPolicy.new(user, record.form).manage? }
  end
end
