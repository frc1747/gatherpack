# Account Status: the rules, each person's result, and setting rules up.
# Everyone who sees some rule's results opens the list and those rules'
# pages, seeing only the people and amounts the rule lets them; admins set
# rules up; architects write custom rules' code.
class Accounting::RulesController < Accounting::BaseController
  EDIT_TABS = %w[ question records people reminders actions enabled ].freeze
  PREVIEW_PEOPLE = 5

  before_action :set_rule, except: %i[ index new create ]

  # GET /accounting/rules
  def index
    authorize AccountingRule
    @rules = policy_scope(AccountingRule).ordered.includes(:gateway, :team)
    @rules = @rules.enabled unless current_user.admin
    @summaries = @rules.to_h { |rule| [ rule.id, Accounting::RuleSummary.new(rule, current_user.person) ] }
    @sources = current_user.admin ? Accounting.sources : []
  end

  # GET /accounting/rules/1
  def show
    @summary = Accounting::RuleSummary.new(@rule, current_user.person)
    load_rows
  end

  # GET /accounting/rules/1/export.csv
  def export
    load_rows
    send_data helpers.accounting_rule_csv(@rule, @rows, @amount_ids), filename: "#{@rule.key}-#{Date.current.iso8601}.csv", type: "text/csv"
  end

  # GET /accounting/rules/new
  def new
    @rule = authorize AccountingRule.new(gateway: Accounting.sources.first, kind: "balance")
    @tab = "question"
  end

  # POST /accounting/rules
  def create
    @rule = authorize AccountingRule.new
    @tab = "question"
    assign(@rule)
    return render(:new, status: :unprocessable_content) unless @rule.errors.empty? && @rule.save

    Accounting::EvaluateRuleJob.perform_later(@rule) if @rule.enabled?
    redirect_to edit_accounting_rule_path(@rule, tab: "records"), notice: "Rule was created. Choose which records count.", status: :see_other
  end

  # GET /accounting/rules/1/edit?tab=records
  def edit
  end

  # PATCH /accounting/rules/1
  def update
    assign(@rule)
    if params[:preview].present?
      @preview = preview(@rule) if @rule.errors.empty? && @rule.valid?
      return render(:edit, status: (@preview ? :ok : :unprocessable_content))
    end
    return render(:edit, status: :unprocessable_content) unless @rule.errors.empty? && @rule.save

    notice = if @rule.enabled?
      Accounting::EvaluateRuleJob.perform_later(@rule)
      "Rule was saved. Results are being worked out again."
    else
      "Rule was saved. It's turned off, so results are worked out when it's turned on."
    end
    redirect_to edit_accounting_rule_path(@rule, tab: @tab), notice: notice, status: :see_other
  end

  # DELETE /accounting/rules/1
  def destroy
    @rule.destroy!
    redirect_to accounting_rules_path, notice: "Rule was deleted.", status: :see_other
  end

  # POST /accounting/rules/1/evaluate
  def evaluate
    unless @rule.enabled?
      return redirect_to accounting_rule_path(@rule), notice: "This rule is turned off. Turn it on to work out results.", status: :see_other
    end

    Accounting::EvaluateRuleJob.perform_later(@rule)
    redirect_to accounting_rule_path(@rule), notice: "Working out everyone's result again. Reload in a minute to see it.", status: :see_other
  end

  # POST /accounting/rules/1/duplicate
  def duplicate
    copy = @rule.duplicate!
    redirect_to edit_accounting_rule_path(copy, tab: "question"),
      notice: "Copied as #{copy.name}, turned off. Check its dates, then turn it on.", status: :see_other
  end

  private
    def set_rule
      @rule = authorize AccountingRule.find(params[:id])
      @tab = params[:tab].presence_in(EDIT_TABS) || "question"
    end

    # The rule page's table: the people the viewer may see, filtered.
    def load_rows
      viewer = current_user.person
      results = Accounting::RuleSummary.new(@rule, viewer).results.includes(person: :teams)
      @value = params[:status].presence
      @teams = Team.where(id: Membership.where(person_id: results.select(:person_id)).select(:team_id)).order(:name)
      @team = @teams.find_by(id: params[:team_id]) if params[:team_id].present?
      results = results.where(value: @value) if @value
      results = results.where(person_id: @team.descendant_people.select(:id)) if @team
      if current_user.admin && params[:unapplied] == "1"
        results = results.where("(accounting_rule_results.details->>'unapplied_credit_cents')::bigint > 0")
      end
      # Only admins see who is on a payment plan.
      @planned_ids = current_user.admin && @rule.balance? ? @rule.planned_person_ids.to_set : Set.new
      results = results.where(person_id: @planned_ids.to_a) if current_user.admin && params[:plan] == "1"
      @rows = results.joins(:person).order("people.last_name", "people.first_name").to_a
      @amount_ids = @rule.amount_people_for(viewer).where(id: @rows.map(&:person_id)).ids.to_set
      @status_only_ids = status_only_ids(viewer)
      @customer_urls = customer_urls if current_user.admin && @rule.capabilities.include?(:deep_links)
    end

    # The people whose milestone line the viewer sees as the status only:
    # on a rule with payment plans, everyone but themselves and their
    # wards. None for admins, or on a rule without plans.
    def status_only_ids(viewer)
      return Set.new if current_user.admin || !@rule.any_plans?

      @rows.select { |result| Accounting::RuleAccess.new(viewer, result.person, @rule).status_only? }.map(&:person_id).to_set
    end

    # Admins' "Open in" link for each person: their first linked customer.
    def customer_urls
      links = AccountingCustomerLink.where(gateway: @rule.gateway, person_id: @rows.map(&:person_id)).order(:created_at)
      urls = @rule.gateway.accounting_records.current.where(role: "customer", customer_external_id: links.select(:customer_external_id))
        .where.not(external_url: nil).pluck(:customer_external_id, :external_url).to_h
      links.each_with_object({}) { |link, found| found[link.person_id] ||= urls[link.customer_external_id] }.compact
    end

    # The form's fields onto the rule. Only architects set code or make a
    # rule custom.
    def assign(rule)
      attributes = rule_params.to_h
      unless policy(rule).write_code?
        attributes.delete(:code)
        rule.errors.add(:kind, "custom can only be chosen by an architect") if attributes[:kind] == "custom" && rule.kind != "custom"
        attributes.delete(:kind) if attributes[:kind] == "custom"
      end
      if attributes.key?(:filters) && attributes[:filters].key?(:min_total)
        typed = attributes[:filters][:min_total]
        attributes[:filters][:min_total] = Accounting.parse_cents(typed)
        rule.errors.add(:base, "Skip records under isn't an amount") if typed.present? && attributes[:filters][:min_total].nil?
      end
      rule.assign_attributes(attributes)
      errors = rule.errors.dup
      rule.valid?
      errors.each { |error| rule.errors.add(error.attribute, error.message) }
    end

    def rule_params
      params.fetch(:accounting_rule, {}).permit(
        :name, :description, :gateway_id, :kind, :code, :team_id, :read_permission, :amount_permission, :enabled,
        :grace_days, :unapplied_credit, :measure, :show_pay_links,
        :remind_days_before, :overdue_every_days, :remind_to, :reminder_level,
        labels: {},
        filters: [ :txn_date_from, :txn_date_to, :due_date_from, :due_date_to, :min_total, { roles: [], items: [], classes: [], locations: [] } ],
        milestones_attributes: %i[ id name due_on balance_at_most balance_at_most_percent position _destroy ],
        badge_grants_attributes: %i[ id badge_id amounts _destroy ],
        actions_attributes: [ :id, :action, :badge_id, :person_field_id, :write, :position, :_destroy,
                              :condition_type, :condition_op, :condition_amount, :condition_count, :condition_values_text, { condition_values: [] } ]
      )
    end

    # The unsaved rule's results for a few of its people: those linked to a
    # customer of its source first, then the team's other members.
    def preview(rule)
      evaluation = Accounting::Evaluation.new(rule)
      linked = Person.where(id: AccountingCustomerLink.where(gateway_id: rule.gateway_id).select(:person_id)).order(:last_name, :first_name).limit(PREVIEW_PEOPLE).to_a
      others = rule.people.where.not(id: linked.map(&:id)).order(:last_name, :first_name).limit(PREVIEW_PEOPLE - linked.size).to_a
      (linked + others).map { |person| [ person, evaluation.outcome_for(person) ] }
    end
end
