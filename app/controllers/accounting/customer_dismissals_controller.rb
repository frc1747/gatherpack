# "Not this person" on a suggested link: that person isn't suggested for
# the customer again. Admins.
class Accounting::CustomerDismissalsController < Accounting::BaseController
  # POST /accounting/customer_dismissals
  def create
    source = find_source(params[:gateway_id])
    authorize source, :customers?, policy_class: Accounting::SourcePolicy
    customer = source.accounting_records.current.where(role: "customer").find(params[:customer_id])
    person = Person.find(params[:person_id])

    Accounting::CustomerLinks.new(source).dismiss!(customer.customer_external_id, person)
    path = params[:back] == "customer" ? accounting_connection_customer_path(source, customer) : accounting_connection_customers_path(source)
    redirect_to path, notice: "#{person.identifier_name} won't be suggested for #{customer.identifier_name} again.", status: :see_other
  end
end
