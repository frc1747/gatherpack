# Linking a source's customer to a person, unlinking, and linking every
# exact name match at once. Admins.
class Accounting::CustomerLinksController < Accounting::BaseController
  # POST /accounting/customer_links
  def create
    authorize AccountingCustomerLink
    source = find_source(params[:gateway_id])
    customer = customer_record(source, params[:customer_id])
    person = Person.find(params[:person_id] || params.dig(:customer_link, :person_id))

    Accounting::CustomerLinks.new(source).link!(customer.customer_external_id, person,
      source: params[:suggested] == "1" ? "confirmed" : "manual", created_by: current_user.person)
    redirect_after(source, customer, "Linked #{customer.identifier_name} to #{person.identifier_name}.")
  end

  # DELETE /accounting/customer_links/:id
  def destroy
    link = authorize policy_scope(AccountingCustomerLink).find(params[:id])
    source = find_source(link.gateway_id)
    customer = source.accounting_records.find_by(role: "customer", customer_external_id: link.customer_external_id)

    Accounting::CustomerLinks.new(source).unlink!(link)
    notice = "Unlinked #{link.person.identifier_name}. They won't be suggested for this customer again."
    customer ? redirect_after(source, customer, notice) : redirect_to(accounting_connection_customers_path(source), notice: notice, status: :see_other)
  end

  # POST /accounting/customer_links/confirm_all
  def confirm_all
    authorize AccountingCustomerLink
    source = find_source(params[:gateway_id])
    links = Accounting::CustomerLinks.new(source)

    made = links.link_exact_names(links.customers.where(active: true), created_by: current_user.person)
    notice = made.any? ? "Linked #{helpers.pluralize(made.size, 'customer')} to the person with the same name." : "No customer has exactly one person with its name."
    redirect_to accounting_connection_customers_path(source), notice: notice, status: :see_other
  end

  private
    def customer_record(source, id)
      source.accounting_records.current.where(role: "customer").find(id)
    end

    # Back to the customer's page when the action came from there, else the
    # Customers page.
    def redirect_after(source, customer, notice)
      path = params[:back] == "customer" ? accounting_connection_customer_path(source, customer) : accounting_connection_customers_path(source)
      redirect_to path, notice: notice, status: :see_other
    end
end
