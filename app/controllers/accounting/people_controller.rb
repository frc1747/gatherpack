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
    # admins. On a rule with plans, anyone else sees only the status
    # (Accounting::RuleAccess#status_only?).
    @plans = @results.to_h { |result| [ result.id, result.on_plan? && access[result.id].sees_plan? ] }
    @status_only = @results.to_h { |result| [ result.id, access[result.id].status_only? ] }
    @statement = Accounting::AccountPolicy.new(current_user, @person).statement?
    # Anyone who may match customers can copy the person's id into a
    # customer's reference field.
    @reference_sources = Accounting.sources.select { |source| source.match_strategy_list.include?("reference") } if Accounting::Access.customer_matcher?(current_user)
    @customer_links = AccountingCustomerLink.where(person: @person).includes(:gateway).order(:created_at) if current_user.admin
  end
end
