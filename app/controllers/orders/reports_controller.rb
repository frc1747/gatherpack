module Orders
  class ReportsController < BaseController
    # GET /orders/reports
    def index
      authorize :order_report
      skip_policy_scope
      @keys = Orders::Reports::KEYS
    end

    # GET /orders/reports/open(.csv)
    def show
      authorize :order_report
      @report = Orders::Reports.new(current_user.person).report(params[:id])
      respond_to do |format|
        format.html
        format.csv do
          send_data Orders::Reports.to_csv(@report), type: "text/csv", filename: "orders-#{@report.key.dasherize}.csv"
        end
      end
    end
  end
end
