module Orders
  # How the viewer hears about approved requests waiting to be bought.
  class NoticePreferencesController < BaseController
    # GET /orders/notice_preference/edit
    def edit
      @preference = authorize OrderNoticePreference.for(current_user.person)
    end

    # PATCH /orders/notice_preference
    def update
      @preference = authorize OrderNoticePreference.for(current_user.person)
      choice = params.dig(:order_notice_preference, :buyer_notices).to_s
      if OrderNoticePreference.buyer_notices.key?(choice) && @preference.update(buyer_notices: choice)
        redirect_to edit_orders_notice_preference_path, notice: "Saved"
      else
        redirect_to edit_orders_notice_preference_path, alert: "Choose one of the options"
      end
    end
  end
end
