# Writes a billing run's charges into its source, one pending line at a
# time, one run at a time per source:
#
# 1. Locks the line and skips it unless it's still pending, so a created
#    line is never sent again.
# 2. With no customer: makes one when the run says so and the source can
#    (emailing the first guardian with an account when the person has
#    guardians, else the person), and links it (source: created); else the
#    line is skipped with the reason. Saved at once, so a charge that then
#    fails doesn't lose the customer: a retry bills that customer.
# 3. Creates the charge with the line's request id, and saves the line as
#    created at once: a retry after a crash returns the first charge
#    instead of a second.
# 4. Then emails it from the source when the run says so and the source
#    can. A crash after the charge is saved never emails it twice.
# 5. Any other error fails the line and fires its failed event. Rate limits
#    and outages are retried with backoff first; past the last try, the
#    lines still pending fail.
# 6. Asks the source to copy the new charge back (QuickBooks fetches it;
#    ledgers sync from their own callbacks).
#
# The run finishes once no line is pending. While the feature is off, or
# once the source can't take charges (QuickBooks' "Let GatherPack create
# invoices" turned off meanwhile), the pending lines fail with the reason,
# so no run waits for ever with nothing to retry.
class Accounting::BillingRunJob < ApplicationJob
  queue_as :default
  # Arguments are records and ids from the books; the log keeps none of them.
  self.log_arguments = false

  limits_concurrency to: 1, key: ->(run) { run.gateway_id }, group: "accounting-billing"

  discard_on ActiveJob::DeserializationError

  retry_on Accounting::TemporaryFailure, wait: :polynomially_longer, attempts: 5 do |job, error|
    run = job.arguments.first
    run.lines.pending.find_each { |line| line.fail!(error.message) }
    run.finish_if_done!
  end

  # Where a person's bills go: the first of their guardians with an
  # account email, when they have guardians, else their own.
  def self.billing_email(person)
    guardian_ids = Relationship.active_guardianships.where(child_id: person.id).order(:created_at).pluck(:parent_id)
    guardians = Person.where(id: guardian_ids).includes(:user).index_by(&:id)
    guardian_ids.filter_map { |id| guardians[id]&.user&.email.presence }.first || person.user&.email
  end

  def perform(run)
    problem = if !Accounting.enabled?
      "Accounting is turned off"
    elsif !run.creates_charges?
      run.gateway.billing_problem
    end

    if problem
      run.lines.pending.find_each { |line| line.fail!(problem) }
    else
      run.lines.pending.pluck(:id).each { |line_id| bill(run, line_id) }
    end
    run.finish_if_done!
  end

  private
    def bill(run, line_id)
      source = run.gateway
      line = AccountingBillingLine.find(line_id)

      line.with_lock do
        next unless line.pending? && line.customer_external_id.blank?

        reason = customer_skip_reason(run)
        next line.skip!(reason) if reason

        line.update!(customer_external_id: create_customer(run, line))
      end

      created = line.with_lock do
        next false unless line.pending?

        line.update!(external_id: source.create_charge(line), status: "created", error: nil)
        true
      end
      return unless created

      send_charge(run, line)
      source.after_billing(line, customer_created: created_customer?(run, line))
    rescue Accounting::TemporaryFailure
      raise
    rescue Accounting::BillingSkipped => e
      AccountingBillingLine.find(line_id).skip!(e.message)
    rescue StandardError, NotImplementedError => e
      Rails.error.report(e, handled: true, context: { billing_line_id: line_id })
      AccountingBillingLine.find(line_id).fail!(e.message)
    end

    def customer_skip_reason(run)
      return "No customer" unless run.create_customers && run.capabilities.include?(:create_customers)

      problem = run.gateway.customer_creation_problem(run.rule&.team)
      "No customer: #{problem}" if problem
    end

    # Whether billing made the line's customer (this run, or an earlier try).
    def created_customer?(run, line)
      run.gateway.accounting_customer_links.exists?(person: line.person, customer_external_id: line.customer_external_id, source: "created")
    end

    def create_customer(run, line)
      person = line.person
      id = run.gateway.create_customer(person, email: self.class.billing_email(person), request_id: line.customer_request_id,
        team: run.rule&.team)
      Accounting::CustomerLinks.new(run.gateway).link!(id, person, source: "created", created_by: run.created_by)
      id
    end

    # A send that fails leaves the line created, with the reason: the
    # charge exists and is never created or sent twice.
    def send_charge(run, line)
      return unless run.send_from_source && run.capabilities.include?(:send_charges)

      email = self.class.billing_email(line.person)
      return line.update!(error: "Created, but not emailed: nobody to email") if email.blank?

      run.gateway.send_charge(line.external_id, email: email)
      line.update!(sent_at: Time.current)
    rescue Accounting::TemporaryFailure, StandardError => e
      line.update!(error: "Created, but not emailed: #{e.message}".truncate(500))
    end
end
