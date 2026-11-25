# A person's Account tab: each rule's result the viewer may see, with
# amounts, charges and pay links where the rule lets them.
class Accounting::PeopleController < Accounting::BaseController
  # GET /people/:person_id/accounting
  def show
    @person = Person.find(params[:person_id])
    authorize @person, :show?, policy_class: Accounting::AccountPolicy
    viewer = current_user.person
    @results = Accounting::Access.visible_results(current_user, @person)
    @amounts = @results.to_h { |result| [ result.id, Accounting::RuleAccess.new(viewer, @person, result.rule).can_see_amounts? ] }
    @statement = Accounting::AccountPolicy.new(current_user, @person).statement?
    @customer_links = AccountingCustomerLink.where(person: @person).includes(:gateway).order(:created_at) if current_user.admin
  end
end
