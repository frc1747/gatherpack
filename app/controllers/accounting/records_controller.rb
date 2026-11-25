# The records copied from a source, as stored: admins check here what a
# sync brought in. No editing.
class Accounting::RecordsController < Accounting::BaseController
  before_action :set_source

  # GET /accounting/connections/:connection_id/records
  def index
    records = policy_scope(AccountingRecord).where(gateway: @source)
    records = records.current unless params[:deleted] == "1"
    records = records.where(role: params[:role]) if AccountingRecord::ROLES.include?(params[:role])
    records = records.where(customer_external_id: params[:customer]) if params[:customer].present?
    records = records.where(txn_date: date_param(:from)..) if date_param(:from)
    records = records.where(txn_date: ..date_param(:to)) if date_param(:to)
    @records = records.order(Arel.sql("txn_date DESC NULLS LAST"), :entity_type, :external_id).page(params[:page])

    customers = @source.accounting_records.where(role: "customer")
    @customer_names = customers.where(customer_external_id: @records.map(&:customer_external_id).compact.uniq).pluck(:customer_external_id, :name).to_h
    @customer_choices = customers.current.order(:name).pluck(:name, :customer_external_id)
  end

  # GET /accounting/connections/:connection_id/records/:id
  def show
    @record = policy_scope(AccountingRecord).where(gateway: @source).find(params[:id])
    @customer = @source.accounting_records.find_by(role: "customer", customer_external_id: @record.customer_external_id) if @record.customer_external_id
  end

  private
    def set_source
      @source = find_source(params[:connection_id])
      authorize @source, :records?, policy_class: Accounting::SourcePolicy
    end

    def date_param(key)
      Date.iso8601(params[key].to_s)
    rescue Date::Error
      nil
    end
end
