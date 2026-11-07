module Checklists
  module Kinds
    # Has a complete response to every chosen form, made (activated) within
    # the item's dates, or at any time. Reads the response's status, so a
    # response that needs confirming again, including one past the form's
    # expiry, isn't done whatever the dates say (spec §6.4):
    #
    # - Done: complete, and the active version was made within the dates.
    # - Almost: a newer version is open, or it waits for a signature.
    # - Not yet: no response, needs confirming again, made before the dates,
    #   the form isn't asking the person, or it needs a guardian's signature
    #   and the person has no guardian linked.
    #
    # A form's expiry (Forms::Expiry, when that feature is present) shows as
    # "Good until <date>" or "Expired <date>".
    class FormComplete < ItemKind
      STATUS_ORDER = %w[not_met pending met].freeze

      class << self
        def label = "Form"
        def description = "Has filled in and signed a form"
        def uses_dates? = true

        def settings
          [
            ItemKind::Setting.new(key: :form_ids, type: :forms, label: "Forms", hint: "All of these"),
            ItemKind::Setting.new(key: :ever, type: :boolean, label: "Any time, whatever the item's dates",
              hint: "Leave unticked to count only responses made within the item's dates")
          ]
        end

        def normalize_config(params)
          config = super
          config["form_ids"] = Array(params.to_h.stringify_keys["form_ids"]).compact_blank if params.to_h.stringify_keys.key?("form_ids")
          config
        end

        def references = { "form_ids" => "Form" }

        def invalidations
          [
            [ ::FormResponse, ->(response) { [ response.subject_id ] } ],
            [ ::FormSubmission, ->(submission) { [ submission.form_response&.subject_id ] } ],
            [ ::FormSignature, ->(signature) { [ signature.form_submission&.form_response&.subject_id ] } ],
            [ ::Relationship, ->(relationship) { [ relationship.parent_id, relationship.child_id ] } ],
            [ ::Form, ->(_form) { :all } ],
            [ ::FormAudienceRule, ->(_rule) { :all } ]
          ]
        end

        def validate(item)
          item.errors.add(:base, "Choose at least one form") if Array(item.config["form_ids"]).compact_blank.empty?
        end

        # Deleted forms; forms nobody can sign (a draft, closed); forms
        # closing inside the item's dates; people covered here the form
        # doesn't ask. The item still evaluates, so nobody passes by accident.
        def problems(item)
          problems = missing_references(item)
          problems << "Forms are turned off, so this counts as not yet for everyone" unless forms_enabled?
          problems << "No form chosen" if Array(item.config["form_ids"]).compact_blank.empty?
          forms = referenced_records(item, "form_ids")
          return problems if forms.empty?

          window = Context.new(item.checklist).window_for(item)
          covered = Population.applicable_ids(item, Population.new(item.checklist).person_ids)
          forms.each do |form|
            problems << "#{form.title} is #{form.draft? ? "a draft" : "closed"}; nobody can sign it" unless form.open?
            if form.open? && form.closes_at && (window.ends_on.nil? || form.closes_at <= window.ends_on.in_time_zone.end_of_day)
              problems << "#{form.title} closes #{I18n.l(form.closes_at.to_date, format: :long)}"
            end
            outside = covered.size - form.audience.where(id: covered).count
            if outside.positive?
              problems << "#{outside} #{outside == 1 ? "person" : "people"} covered here #{outside == 1 ? "isn't" : "aren't"} asked #{form.title}; add the checklist to its audience"
            end
          end
          problems
        end

        def describe(item)
          titles = referenced_records(item, "form_ids").map(&:title)
          "Completes #{titles.to_sentence.presence || "a form"}#{" (any time)" if item.config["ever"]}"
        end

        # The earliest coming expiry among the forms' complete responses, and
        # midnight for a "within the last N" window.
        def next_change_at(item, context)
          times = referenced_records(item, "form_ids").filter_map { |form| next_expiry(form, context.as_of) }
          relative = item.starts_within_amount.present? || (!Window.own_start?(item) && context.checklist.starts_within_amount.present?)
          times << context.as_of.to_date.tomorrow.in_time_zone.beginning_of_day if relative && !item.config["ever"]
          times.min
        end

        def forms_enabled?
          GatherPack::Features.enabled?(:forms)
        end

        private

        def next_expiry(form, now)
          return unless form.respond_to?(:expires?) && form.expires?

          signed = ::FormResponse.where(form: form, status: :complete).joins(:active_submission)
          if form.expires_on
            at = form.expiry_for(nil)
            at if at > now && signed.exists?
          else
            first = signed.where("form_submissions.activated_at > ?", now - form.valid_for_months.months).minimum("form_submissions.activated_at")
            first && form.expiry_for(first)
          end
        end
      end

      def evaluate(person_ids)
        return person_ids.index_with { Result.not_met("Unavailable", detail: "Forms are turned off") } unless self.class.forms_enabled?

        forms = self.class.referenced_records(item, "form_ids")
        return person_ids.index_with { Result.not_met("Form missing", detail: "The form this item uses was deleted") } if forms.empty?

        people = ::Person.where(id: person_ids).index_by(&:id)
        responses = ::FormResponse.where(form: forms, subject_id: person_ids)
          .includes(:active_submission, form_submissions: :form_signatures).group_by(&:form_id)
          .transform_values { |list| list.index_by(&:subject_id) }
        asked = forms.to_h { |form| [ form.id, form.audience.where(id: person_ids).pluck(:id).to_set ] }
        guardians = guardians_by_ward(person_ids)

        person_ids.index_with do |person_id|
          results = forms.map do |form|
            [ form, form_result(form, people[person_id], responses.dig(form.id, person_id), asked[form.id].include?(person_id), guardians[person_id]) ]
          end
          combine(results)
        end
      end

      private

      def form_result(form, person, response, asked, guardians)
        submission = response&.active_submission
        signed_at = submission&.activated_at

        if response&.complete? && signed_at && (config["ever"] || window.cover?(signed_at))
          return Result.met("Completed #{day(signed_at)}", detail: sentence("Completed #{day(signed_at)}", expiry(response)))
        end

        unless asked
          return Result.not_met("Not asked", detail: "This form isn't asking them; add them to its audience",
            fix: { "label" => "Add them to the form's audience", "path" => routes.edit_form_path(form, tab: "audience") })
        end

        if needs_guardian?(form, person, guardians)
          return Result.not_met("Needs a guardian linked", detail: "Needs a guardian linked: a guardian signs this form",
            fix: { "label" => "Add a guardian", "path" => routes.relationships_person_path(person) })
        end

        if (open = response&.open_submission)
          return open_result(form, person, open, guardians)
        end

        if response&.needs_reconfirmation?
          return reconfirmation_result(form, person, response)
        end

        if response&.complete?
          return Result.not_met("Needs doing again", detail: sentence("Completed #{day(signed_at)}, #{outside_window(signed_at)}", expiry(response)),
            fix: { "label" => "Do it again", "path" => routes.edit_form_response_path(form, person) })
        end

        Result.not_met(response&.withdrawn? ? "Withdrawn" : "Not started",
          detail: response&.withdrawn? ? "The response was withdrawn" : "No response yet",
          fix: { "label" => "Fill it in", "path" => routes.edit_form_response_path(form, person) })
      end

      def open_result(form, person, submission, guardians)
        if submission.pending?
          waiting = waiting_for(submission, person, guardians)
          Result.pending(waiting, detail: waiting, fix: { "label" => "Sign it", "path" => routes.form_response_path(form, person) })
        else
          Result.pending("Started", detail: "A new version is started but not submitted",
            fix: { "label" => "Finish it", "path" => routes.edit_form_response_path(form, person) })
        end
      end

      def reconfirmation_result(form, person, response)
        reason = response.reconfirmation_reason
        summary = reason == :expired ? expiry(response) : "Needs confirming again"
        detail = case reason
        when :expired then expiry(response)
        when :profile then "Needs confirming again: their profile details changed"
        else "Needs confirming again: the form changed"
        end
        Result.not_met(summary, detail: detail, fix: { "label" => "Confirm it again", "path" => routes.edit_form_response_path(form, person) })
      end

      # "Waiting for Pat World's signature" for a guardian's; the form's own
      # words for anything else.
      def waiting_for(submission, person, guardians)
        missing = submission.missing_signatures
        return "Waiting for #{submission.waiting_for.to_sentence.presence || "it to be checked"}" if missing.empty?

        roles = missing.flat_map { |question| FormAccess.signer_roles(question, person) }.uniq
        if roles.include?(:guardian) && guardians.present?
          names = guardians.map { |guardian| "#{guardian.identifier_name}'s" }
          "Waiting for #{names.to_sentence(two_words_connector: " or ", last_word_connector: " or ")} signature"
        elsif roles == [ :subject ]
          "Waiting for their signature"
        else
          "Waiting for #{missing.first.signer_description}'s signature"
        end
      end

      # A signature only a guardian may give, for someone with no guardian.
      def needs_guardian?(form, person, guardians)
        return false if guardians.present? || person.nil?

        form.signature_questions.any? { |question| FormAccess.signer_roles(question, person) == [ :guardian ] }
      end

      def guardians_by_ward(person_ids)
        pairs = ::Relationship.active_guardianships.where(child_id: person_ids).pluck(:child_id, :parent_id)
        people = ::Person.where(id: pairs.map(&:last)).order(:first_name, :last_name).index_by(&:id)
        pairs.group_by(&:first).transform_values { |list| list.filter_map { |_, parent_id| people[parent_id] } }
      end

      # All of the forms: the first not done decides, then the first almost.
      def combine(results)
        return results.first.last if results.one?

        worst = results.min_by { |_, result| STATUS_ORDER.index(result.status) }.last
        done = results.count { |_, result| result.met? }
        detail = results.map { |form, result| "#{form.title}: #{result.detail}" }.join(". ")
        Result.new(status: worst.status, summary: "#{done} of #{results.size} forms done", detail: detail, fix: worst.fix)
      end

      def expiry(response)
        response.expiry_summary if response.respond_to?(:expiry_summary)
      end

      def outside_window(time)
        if window.start_time && time < window.start_time
          "before #{day(window.starts_on)}"
        else
          "after #{day(window.ends_on || window.as_of)}"
        end
      end

      def sentence(*parts)
        parts.compact_blank.join(". ")
      end

      def day(date)
        I18n.l(date.to_date, format: :long)
      end

      def routes
        Rails.application.routes.url_helpers
      end
    end
  end
end
