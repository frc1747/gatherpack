# A person's statement: the records behind the rules whose amounts the
# viewer may see, with a running balance. Read only.
class Accounting::StatementsController < Accounting::BaseController
  # GET /people/:person_id/accounting/statement
  def show
    @person = Person.find(params[:person_id])
    authorize @person, :statement?, policy_class: Accounting::AccountPolicy
    @statement = Accounting::Statement.new(current_user.person, @person)
  end
end
