# Approval of an order request (spec §3.3). The steps come from the
# orders_approval_steps setting, keyed by a stable step_key; a request needs
# every step whose minimum its total meets, in order, and at least the
# first. Approvals a material change voids keep their row with cleared_at
# set, so the timeline still shows them.
#
# Works on loaded associations, so Orders::WaitingOn can preload approvals
# and lines and find many requests' current steps without a query each.
module Orders
  module ApprovalEngine
    extend ActiveSupport::Concern

    DECISIONS = %w[approved changes_requested declined].freeze

    def approval_steps
      Orders::Config.approval_steps
    end

    # The steps this request's total needs, in order.
    def needed_steps(steps = approval_steps)
      needed = steps.select { |step| total_cents >= step.minimum_cents }
      needed.presence || steps.first(1)
    end

    def final_step(steps = approval_steps)
      needed_steps(steps).last
    end

    def active_approvals
      order_approvals.select { |approval| approval.cleared_at.nil? }
    end

    def approved_step_keys
      active_approvals.select(&:approved?).map(&:step_key)
    end

    # The first needed step without a standing approval, while submitted.
    # When every needed step already has one (an edit lowered the total
    # under a later step's minimum), the final needed step, so an approver
    # confirms it with the final checks rather than it approving itself.
    def current_step(steps = approval_steps)
      return nil unless submitted?

      keys = approved_step_keys
      needed = needed_steps(steps)
      needed.find { |step| keys.exclude?(step.key) } || needed.last
    end

    # Every step the total needs has a standing approval.
    def all_steps_approved?(steps = approval_steps)
      keys = approved_step_keys
      needed_steps(steps).all? { |step| keys.include?(step.key) }
    end

    # The step a decision now would be on: the current step, or the final
    # step for lines that need re-approval. Nil when nothing is waiting.
    def decision_step(steps = approval_steps)
      return current_step(steps) if submitted?
      return final_step(steps) if needs_reapproval?

      nil
    end

    # Whether the person may approve, ask for changes on or decline the
    # request now: an approver on the decision step who didn't make it and
    # isn't related to whoever did. Watching it doesn't matter.
    def can_decide?(person, steps = approval_steps)
      step = decision_step(steps)
      return false if step.nil? || person.nil?

      access = Orders::Access.for(person)
      access.approver_on?(step, team_id) && !access.own_or_relative?(self)
    end

    # Why the person can't decide, for the page to say, or nil.
    def decision_refusal(person)
      step = decision_step
      return "Nothing is waiting for a decision." if step.nil?

      access = Orders::Access.for(person)
      return "You made this request, so another approver has to decide." if person && requested_by_id == person.id
      return "A relative made this request, so another approver has to decide." if access.own_or_relative?(self)
      return "You aren't an approver for #{step.name} on #{team.name}." unless access.approver_on?(step, team_id)

      nil
    end

    # The restricted funding sources the request uses.
    def restricted_sources
      funding_sources_used.select(&:restricted?)
    end

    # Records an approver's decision. decision is :approved,
    # :changes_requested or :declined; the latter two need a comment.
    # Approving a request that uses a restricted source needs
    # fits_restriction: true.
    def decide!(decision, by:, comment: nil, fits_restriction: false)
      decision = decision.to_s
      raise Orders::Refused, "Unknown decision." unless DECISIONS.include?(decision)

      locked do
        steps = approval_steps
        step = decision_step(steps)
        refusal = decision_refusal(by)
        raise Orders::Refused, refusal if refusal
        if decision != "approved" && comment.blank?
          raise Orders::Refused, "Say what needs changing or why it's declined."
        end

        reapproval = !submitted?
        if reapproval && decision == "changes_requested"
          raise Orders::Refused, "Approve or decline the changed items."
        end

        changes = {}
        if decision == "approved"
          if restricted_sources.any?
            raise Orders::Refused, "Confirm the request fits the funding restriction." unless fits_restriction
            changes["fits_restriction"] = true
          end
          final = reapproval || needed_steps(steps).all? { |s| s.key == step.key || approved_step_keys.include?(s.key) }
          if final && Orders::Config.require_funding_source? && live_lines.any? { |line| line.effective_funding_source_id.nil? }
            raise Orders::Refused, "Choose a funding source before the final approval."
          end
        end

        order_approvals.create!(step_key: step.key, approver: by, decision: decision, comment: comment.presence)
        reapproval ? record_reapproval(decision, step, by, comment, changes) : record_decision(decision, step, steps, by, comment, changes)
      end
    end

    private

    def record_decision(decision, step, steps, by, comment, changes)
      case decision
      when "approved"
        self.approved_total_cents = total_cents
        if all_steps_approved?(steps)
          live_lines.each { |line| line.update!(status: :approved) if line.pending? }
          update!(status: :approved, approved_at: Time.current)
          changes["status"] = %w[submitted approved]
        else
          save!
        end
        log!(:approved, by: by, step_key: step.key, changes: changes, comment: comment)
      when "changes_requested"
        update!(status: :changes_requested)
        log!(:changes_requested, by: by, step_key: step.key, comment: comment)
      when "declined"
        update!(status: :declined)
        log!(:declined, by: by, step_key: step.key, comment: comment)
      end
    end

    def record_reapproval(decision, step, by, comment, changes)
      lines = reapproval_lines
      lines.each do |line|
        if decision == "approved"
          line.update!(status: line.purchase_id ? :ordered : :approved)
        else
          line.update!(status: :cancelled)
        end
      end
      changes["lines"] = lines.map(&:display_name)
      self.approved_total_cents = total_cents if decision == "approved"
      save!
      refresh_status_from_lines
      log!(decision, by: by, step_key: step.key, changes: changes, comment: comment)
    end
  end
end
