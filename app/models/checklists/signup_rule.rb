module Checklists
  # The checklist kind of sign-up position rule (spec §10.3): only people
  # who finish the checklist can take the place, or, with accept_pending,
  # people who are almost done too (where signing up is how they finish).
  # A met or exempt overall passes; someone the checklist doesn't cover
  # never does. Read from stored results, computing anyone not yet stored
  # (Checklists::Reader), so a rule follows the checklist's refreshes.
  #
  # With checklists turned off, or the checklist a draft or archived, the
  # rule fails with its reason, never a silent pass.
  #
  # The answer depends on who is looking (Checklists::SignupViewer: the
  # viewer of the sheet page or roster, or whoever places or moves a
  # sign-up). The person gets their own answer, and so does anyone who may
  # see the person's overall, uncapped by any item's kind (spec §10.1).
  # Anyone else, whether they sign the person up from the sheet page or run
  # the sheet, sees nothing for the rule, and placing is refused with a
  # reason that doesn't depend on the person, even against the rules. (A
  # refusal itself still tells them the person doesn't pass.) With no
  # viewer set the rule gives its real answer.
  #
  # Prepended to SignupPositionRule by config/initializers/checklists_signups.rb.
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
      return "#{checklist_requirement} (#{checklist.title} #{checklist.draft? ? "is a draft" : "is archived"})" unless checklist.active?


      viewer = Checklists::SignupViewer.person
      return (hidden_reason if Checklists::SignupViewer.placing) unless viewer.nil? || sees_result?(viewer, person)

      checklist_requirement unless accepted_statuses.include?(checklist_status(person))
    end

    # The fixed reason when viewer may not learn whether the person passes,
    # else nil.
    def hidden_reason_for(person, viewer)
      return unless checklist? && checklist&.active? && Checklists.enabled? && viewer && person

      hidden_reason unless sees_result?(viewer, person)
    end

    # Whether viewer may learn the person's result through the rule: they
    # are the person, or they see the person's overall and no item's kind
    # caps it for them. Being able to sign someone up isn't enough.
    def sees_result?(viewer, person)
      return true if viewer.id == person.id

      @sees_result ||= {}
      @sees_result.fetch([ viewer.id, person.id ]) do
        @sees_result[[ viewer.id, person.id ]] = Checklists.status_for(checklist, [ person ], viewer: viewer)[person.id]&.overall.present? &&
          Checklists.capped_person_ids(checklist.top_level_items.to_a, viewer, [ person.id ]).empty?
      end
    end

    # The checklist's overall for the person (met, pending, not_met, exempt),
    # or nil when it doesn't cover them. Only an active checklist answers:
    # a draft's results are for the people running it, and an archived
    # one's are frozen.
    def checklist_status(person)
      return if checklist.nil? || person.nil? || !checklist.active?

      @checklist_statuses ||= {}
      return @checklist_statuses[person.id] if @checklist_statuses.key?(person.id)

      @checklist_statuses[person.id] = Checklists::Reader.new(checklist, nil).overall_statuses([ person.id ])[person.id]
    end

    def accepted_statuses
      accept_pending? ? %w[met exempt pending] : %w[met exempt]
    end

    def reload(...)
      @checklist_statuses = @sees_result = nil
      super
    end

    private

    def hidden_reason
      "You can't see their #{checklist.title} results, so can't sign them up here"
    end

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
