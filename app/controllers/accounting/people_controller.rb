# A person's Account tab: each rule's result the viewer may see, with
# amounts, charges and pay links where the rule lets them, and for admins
# each balance rule's Payment plan.
class Accounting::PeopleController < Accounting::BaseController
  # GET /people/:person_id/accounting
  def show
    @person = Person.find(params[:person_id])
    authorize @person, :show?, policy_class: Accounting::AccountPolicy
    viewer = current_user.person
    @results = Accounting::Access.visible_results(current_user, @person)
    access = @results.to_h { |result| [ result.id, Accounting::RuleAccess.new(viewer, @person, result.rule) ] }
    @amounts = access.transform_values(&:can_see_amounts?)
    # A payment plan's milestones show to the person, their guardians and
    # admins; to anyone else the person's milestone line is only the status.
    @plans = @results.to_h { |result| [ result.id, result.on_plan? && access[result.id].sees_plan? ] }
    @plan_hidden = @results.to_h { |result| [ result.id, access[result.id].plan_hidden?(result) ] }
    @statement = Accounting::AccountPolicy.new(current_user, @person).statement?
    @customer_links = AccountingCustomerLink.where(person: @person).includes(:gateway).order(:created_at) if current_user.admin
  end
end
