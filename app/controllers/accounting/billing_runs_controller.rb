# Bill people: what to charge and who, a preview with a row per person, then
# a billing run whose lines Accounting::BillingRunJob writes into the
# source. A source that can't create charges gets a CSV in the file
# source's layout instead. Admins bill from a rule or from Account Status;
# holders of a rule's badge grant with bill on bill from that rule only,
# its people and items (Accounting::BillingAccess).
class Accounting::BillingRunsController < Accounting::BaseController
  before_action :set_run, only: %i[ show export retry_failed ]

  # GET /accounting/billing_runs
  def index
    authorize AccountingBillingRun
    @runs = policy_scope(AccountingBillingRun).newest_first.includes(:gateway, :rule, :created_by).to_a
    @counts = AccountingBillingLine.where(run_id: @runs.map(&:id)).group(:run_id, :status).count
  end

  # GET /accounting/billing_runs/new?gateway_id=1
  # GET /accounting/rules/1/billing_runs/new
  def new
    @rule = AccountingRule.find(params[:rule_id]) if params[:rule_id]
    @run = authorize AccountingBillingRun.new(rule: @rule, gateway: @rule&.gateway || chosen_source), :new?
    return @sources = Accounting.sources if @run.gateway.nil?

    @run.txn_date = Date.current
    @who = @rule&.balance? ? "not_invoiced" : "team"
    @access = Accounting::BillingAccess.new(current_user.person, @rule)
  end

  # POST /accounting/billing_runs
  # POST /accounting/rules/1/billing_runs
  #
  # With preview, shows the rows; otherwise saves the run from them.
  def create
    @rule = AccountingRule.find(params[:rule_id]) if params[:rule_id]
    @run = authorize AccountingBillingRun.new(rule: @rule, gateway: @rule&.gateway || chosen_source, created_by: current_user.person, status: "running"), :create?
    raise ActiveRecord::RecordNotFound if @run.gateway.nil?

    @access = Accounting::BillingAccess.new(current_user.person, @rule)
    assign_run
    @preview = build_preview
    @rows = preview_rows

    return render(:new, status: (@errors.empty? ? :ok : :unprocessable_content)) if params[:preview].present? || @errors.any?

    build_lines
    if @errors.empty? && @run.lines.empty?
      @errors << "Tick at least one person to bill."
    elsif @errors.empty? && @run.creates_charges? && params[:confirm] != "yes"
      @errors << "Choose \"Yes, create them\" to create the #{charge_word.pluralize}."
    end
    return render(:new, status: :unprocessable_content) if @errors.any?

    @run.creates_charges? ? start_run : export_run
  end

  # GET /accounting/billing_runs/1
  def show
    @lines = @run.lines.includes(:person).to_a
    @details = @run.details
    @customer_names = @run.gateway.accounting_records.where(role: "customer", customer_external_id: @lines.map(&:customer_external_id).compact)
      .pluck(:customer_external_id, :name).to_h.compact_blank
  end

  # GET /accounting/billing_runs/1/export.csv
  def export
    export = Accounting::Files::BillingExport.new(@run)
    send_data export.csv, filename: export.filename, type: "text/csv"
  end

  # POST /accounting/billing_runs/1/retry_failed
  def retry_failed
    unless @run.creates_charges? && @run.lines.failed.exists?
      return redirect_to accounting_billing_run_path(@run), notice: "Nothing to try again.", status: :see_other
    end

    @run.retry_failed!(Accounting::BillingAccess.new(current_user.person, @run.rule))
    redirect_to accounting_billing_run_path(@run), notice: "Trying the failed lines again. Reload in a minute to see how it went.", status: :see_other
  end

  private
    def set_run
      @run = authorize AccountingBillingRun.find(params[:id])
    end

    def chosen_source
      id = params[:gateway_id].presence
      find_source(id) if id
    end

    def run_params
      params.fetch(:run, {}).permit(:item_external_id, :amount, :txn_date, :due_on, :memo, :create_customers, :send_from_source)
    end

    # The form's What and More choices onto the run; problems in @errors.
    def assign_run
      @errors = []
      values = run_params
      @run.item_external_id = values[:item_external_id].presence
      @run.amount_cents = Accounting.parse_cents(values[:amount])
      @run.txn_date = parse_date(values[:txn_date], "The invoice date") || Date.current
      @run.due_on = parse_date(values[:due_on], "The due date") if @run.capabilities.include?(:due_dates)
      @run.memo = values[:memo].to_s.strip.presence
      @run.create_customers = boolean(values[:create_customers]) && @run.capabilities.include?(:create_customers)
      @run.send_from_source = boolean(values[:send_from_source]) && @run.capabilities.include?(:send_charges)

      @errors << "Choose what to charge for." unless @access.items(@run.gateway).exists?(external_id: @run.item_external_id)
      @errors << "The amount isn't an amount above zero." unless @run.amount_cents&.positive?
      @errors << "The due date can't be before the invoice date." if @run.due_on && @run.due_on < @run.txn_date
      @who = params[:who].presence_in(Accounting::BillingPreview.who_choices(@rule)) || Accounting::BillingPreview.who_choices(@rule).first
    end

    def build_preview
      team = Team.find_by(id: params[:team_id]) if params[:team_id].present?
      @errors << "Choose a team." if @who == "team" && team.nil?
      # Rows from an earlier Pick people preview stay picked; rows from a
      # preview of a team or the Not invoiced people don't carry over.
      person_ids = Array(params[:person_ids])
      person_ids += posted_rows.keys if params[:previous_who] == "people"
      person_ids += searched_people.map(&:id) if @who == "people"
      Accounting::BillingPreview.new(@run, access: @access, who: @who, team: team, person_ids: person_ids.uniq)
    end

    # People matching the search, to add to the picked people.
    def searched_people
      return [] if params[:person_q].blank?

      @access.people.ransack(first_name_or_last_name_or_display_name_i_cont: params[:person_q]).result
        .order(:last_name, :first_name).limit(Accounting::BillingPreview::SEARCH_LIMIT).to_a
    end

    # The preview's rows, with what the form already said about each:
    # ticked, their customer and an amount of their own. A tick given
    # beside a different warning (or none) doesn't stand: the row starts
    # as its new warning says.
    def preview_rows
      @preview.rows.map do |row|
        posted = posted_rows[row.person.id]
        next row unless posted

        included = posted[:warning].to_s == row.warning.to_s ? boolean(posted[:include]) : row.included
        customer_id = posted[:customer].presence_in(row.customers.map(&:customer_external_id)) || row.customer_id
        row.with(included: included, customer_id: customer_id)
      end
    end

    # rows[<person id>][include|customer|amount], as the preview posts them.
    def posted_rows
      @posted_rows ||= begin
        rows = params.fetch(:rows, {})
        rows.permit(rows.keys.index_with { %i[ include customer amount warning ] }).to_h.transform_values(&:symbolize_keys)
      end
    end

    # A line for each row the preview showed ticked; only the preview's
    # people can be billed.
    def build_lines
      @rows.select { |row| row.included && posted_rows.key?(row.person.id) }.each do |row|
        typed = posted_rows.dig(row.person.id, :amount)
        amount = typed.present? ? Accounting.parse_cents(typed) : @run.amount_cents
        next @errors << "#{row.person.identifier_name}: the amount isn't an amount above zero." unless amount&.positive?

        @run.lines.build(person: row.person, customer_external_id: row.customer_id, amount_cents: amount)
      end
    end

    def start_run
      AccountingBillingRun.transaction { @run.save! }
      Accounting::BillingRunJob.perform_later(@run)
      redirect_to accounting_billing_run_path(@run),
        notice: "Creating #{helpers.pluralize(@run.lines.size, charge_word)} in #{@run.gateway.source_name}. Reload in a minute to see how it went.",
        status: :see_other
    end

    # No live create: the lines with a customer go in the CSV, the rest are
    # skipped, and the run is finished. The CSV is downloaded from the run's
    # page, so clicking twice can't make a second run.
    def export_run
      @run.lines.each do |line|
        line.status = line.customer_external_id.present? ? "exported" : "skipped"
        line.error = "No customer" if line.skipped?
      end
      AccountingBillingRun.transaction { @run.save! }
      @run.finish_if_done!
      redirect_to accounting_billing_run_path(@run), status: :see_other,
        notice: "Saved #{helpers.pluralize(@run.lines.count(&:exported?), charge_word)} for the CSV. Download it and import it into your accounting program."
    end

    def charge_word
      helpers.accounting_charge_word(@run.gateway)
    end

    def parse_date(text, name)
      return nil if text.blank?

      Date.iso8601(text.to_s)
    rescue Date::Error
      @errors << "#{name} isn't a date."
      nil
    end

    def boolean(value)
      ActiveModel::Type::Boolean.new.cast(value) == true
    end
end
