module Checklists
  # The checklist kind of sign-up position rule (spec §10.3): only people
  # who finish the checklist can take the place, or, with accept_pending,
  # people who are almost done too (where signing up is how they finish).
  # A met or exempt overall passes; someone the checklist doesn't cover
  # never does. Read from stored results, computing anyone not yet stored
  # (Checklists::Reader), so a rule follows the checklist's refreshes.
  #
  # With checklists turned off the rule fails with its reason, never a
  # silent pass. Prepended to SignupPositionRule by
  # config/initializers/checklists_signups.rb.
  module SignupRule
    extend ActiveSupport::Concern

    prepended do
      belongs_to :checklist, optional: true

      validate :checklist_chosen, if: :checklist?
      before_validation :clear_checklist_settings
    end

    def description
      return super unless checklist?

      checklist_requirement
    end

    def check(person, event)
      return super unless checklist?
      return checklist_requirement if checklist.nil?
      return "#{checklist_requirement} (checklists are turned off)" unless Checklists.enabled?

      checklist_requirement unless accepted_statuses.include?(checklist_status(person))
    end

    # The checklist's overall for the person (met, pending, not_met, exempt),
    # or nil when it doesn't cover them.
    def checklist_status(person)
      return if checklist.nil? || person.nil?

      @checklist_statuses ||= {}
      return @checklist_statuses[person.id] if @checklist_statuses.key?(person.id)

      @checklist_statuses[person.id] = Checklists::Reader.new(checklist, nil).overall_statuses([ person.id ])[person.id]
    end

    def accepted_statuses
      accept_pending? ? %w[met exempt pending] : %w[met exempt]
    end

    def reload(...)
      @checklist_statuses = nil
      super
    end

    private

    # "Needs Trip Eligibility: Done", "Needs Trip Eligibility: Done or Almost",
    # in the checklist's own words.
    def checklist_requirement
      return "Needs a checklist that no longer exists" if checklist.nil?

      words = [ checklist.word_for("met") ]
      words << checklist.word_for("pending") if accept_pending?
      "Needs #{checklist.title}: #{words.join(" or ")}"
    end

    def checklist_chosen
      errors.add(:base, "Choose a checklist") if checklist.nil?
    end

    def clear_checklist_settings
      return if checklist?

      self.checklist_id = nil
      self.accept_pending = false
    end
  end
end
