# Mixed into ManagedListsController (config/initializers/orders.rb): a row
# whose model refuses a change made with a bang method there (retire! or
# restore!, such as retiring the last active payment method) goes back to
# the list with the reason, rather than an error page.
module Orders
  module ManagedListRefusals
    extend ActiveSupport::Concern

    included do
      rescue_from ActiveRecord::RecordInvalid do |error|
        flash[:danger] = error.record.errors.full_messages.to_sentence
        redirect_to managed_list_path(params[:list]), status: :see_other
      end
    end
  end
end
