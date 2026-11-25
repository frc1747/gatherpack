# The Customers page of a source: which people each customer is for.
# Admins link suggested people, pick someone else, or say a suggestion is
# wrong. Rules only see customers that are linked.
class Accounting::CustomersController < Accounting::BaseController
  include SearchAndAdd

  before_action :set_source
  before_action :set_customer, only: %i[ show candidates ]

  # GET /accounting/connections/:connection_id/customers
  def index
    @show_inactive = params[:inactive] == "1"
    customers = @links.customers.order(:name, :customer_external_id)
    customers = customers.where(active: true) unless @show_inactive

    links = policy_scope(AccountingCustomerLink).where(gateway: @source).includes(:person).order(:created_at)
    @links_by_customer = links.group_by(&:customer_external_id)
    @rolled_up = customers.to_h { |customer| [ customer.customer_external_id, @links.rolled_up_into(customer.customer_external_id, @links_by_customer.keys) ] }.compact
    @linked, @unlinked = customers.partition { |customer| covered?(customer) }
    @suggestions = @links.suggestions_for(@unlinked)
    @parent_names = @links.customers.where(customer_external_id: @rolled_up.values).pluck(:customer_external_id, :name).to_h
  end

  # GET /accounting/connections/:connection_id/customers/:id
  def show
    id = @customer.customer_external_id
    @customer_links = policy_scope(AccountingCustomerLink).where(gateway: @source, customer_external_id: id).includes(:person).order(:created_at)
    @suggestions = @links.suggestions_for([ @customer ])[id]
    @rolled_up_into = @links.customers.find_by(customer_external_id: @links.rolled_up_into(id))
    @parent = @links.customers.find_by(customer_external_id: @customer.parent_external_id) if @customer.parent_external_id
    @sub_customers = @links.customers.where(parent_external_id: id).order(:name)
    @records = @source.accounting_records.current.where(customer_external_id: id).where.not(role: "customer")
      .order(Arel.sql("txn_date DESC NULLS LAST"), :external_id).page(params[:page])
    load_person_candidates
  end

  # GET /accounting/connections/:connection_id/customers/:id/candidates
  def candidates
    load_person_candidates
  end

  private
    def set_source
      @source = find_source(params[:connection_id])
      authorize @source, :customers?, policy_class: Accounting::SourcePolicy
      @links = Accounting::CustomerLinks.new(@source)
    end

    def set_customer
      @customer = @links.customers.find(params[:id])
    end

    def covered?(customer)
      @links_by_customer.key?(customer.customer_external_id) || @rolled_up.key?(customer.customer_external_id)
    end

    # People not linked to this customer yet, for the person picker.
    def load_person_candidates
      linked = AccountingCustomerLink.where(gateway: @source, customer_external_id: @customer.customer_external_id).select(:person_id)
      load_candidates(Person.where.not(id: linked).order(:last_name, :first_name), :first_name_or_last_name_or_display_name_i_cont)
    end
end
