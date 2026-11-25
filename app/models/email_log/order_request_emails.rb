module EmailLog
  # The approvers emailed for each approval step of an order request, from
  # the sent email log: when each was first emailed while the step waited,
  # and when they first clicked a link in one of those emails. Shown on the
  # request's page to the people who can approve or manage it, while both
  # the email log and orders are on.
  class OrderRequestEmails
    Approver = Data.define(:person, :emailed_at, :link_clicked_at, :problem)
    Step = Data.define(:step, :approvers)

    def self.visible?(order_request, person)
      return false unless person && EmailLog.enabled? && Orders.enabled?

      access = Orders::Access.for(person)
      return true if access.admin?
      return false if access.own_or_relative?(order_request)

      access.any_approver_team_ids.include?(order_request.team_id) || access.manages?(order_request.team_id)
    end

    def initialize(order_request)
      @order_request = order_request
    end

    # The steps the request has reached, each with the approvers emailed
    # while it waited. Empty when nothing about the request was logged.
    def steps
      return [] if emails.empty?

      reached_steps.map do |step, from, to|
        sent = emails.select { |email| within?(sent_time(email), from, to) }
        Step.new(step: step, approvers: approvers_for(step, sent))
      end
    end

    private
      attr_reader :order_request

      def emails
        @emails ||= SentEmail.where(about: order_request).where.not(person_id: nil).includes(:person).to_a
      end

      # Each needed step the request got to, with the times it began and
      # ended waiting: from the approval of the step before (the first step
      # from the start) to its own approval (still waiting: no end).
      def reached_steps
        approved_at = order_request.active_approvals.select(&:approved?).to_h { |approval| [ approval.step_key, approval.created_at ] }
        from = nil
        order_request.needed_steps.each_with_object([]) do |step, reached|
          to = approved_at[step.key]
          reached << [ step, from, to ]
          break reached unless to

          from = to
        end
      end

      # The emailed people who may decide the step, with their first email
      # in its window and their first link click in any of them.
      def approvers_for(step, step_emails)
        step_emails.group_by(&:person).filter_map do |person, sent|
          access = Orders::Access.new(person)
          next unless access.approver_on?(step, order_request.team_id) && !access.own_or_relative?(order_request)

          latest = sent.max_by { |email| sent_time(email) }
          Approver.new(person: person, emailed_at: sent.map { |email| sent_time(email) }.min,
            link_clicked_at: sent.filter_map(&:link_clicked_at).min, problem: (latest.status_label if latest.problem?))
        end.sort_by { |approver| approver.person.identifier_name.to_s }
      end

      def within?(at, from, to)
        (from.nil? || at >= from) && (to.nil? || at <= to)
      end

      def sent_time(email)
        email.sent_at || email.created_at
      end
  end
end
