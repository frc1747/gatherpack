module Checklists
  # Placing or moving a sign-up checks a checklist rule as the person doing
  # it (Checklists::SignupRule): when the person fails and the placer may
  # not see their result, it's refused with a fixed reason, even when
  # placing against the rules, since nobody overrides a failure they can't
  # see.
  # Prepended to Signup by config/initializers/checklists_signups.rb.
  module SignupPlacement
    private

    def rule_problems(by, organizer, override_rules)
      Checklists::SignupViewer.set(person: by, placing: true) do
        hidden = signup_position.signup_position_rules.select(&:checklist?).filter_map { |rule| rule.hidden_reason_for(person, by) }
        (super(by, organizer, override_rules) + hidden).uniq
      end
    end
  end
end
