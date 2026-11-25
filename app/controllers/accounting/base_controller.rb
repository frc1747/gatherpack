# Accounting screens: refused while the feature is off.
class Accounting::BaseController < InternalController
  before_action :require_feature

  private
    def require_feature
      redirect_to root_path, notice: "Accounting is turned off" unless Accounting.enabled?
    end

    # The accounting source a route names.
    def find_source(id)
      source = Gateway.find(id)
      raise ActiveRecord::RecordNotFound unless source.is_a?(Accounting::Provider)

      source
    end
end
