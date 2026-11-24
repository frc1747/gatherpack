class PrintStylesController < InternalController
  before_action :check_for_admin

  def update
    authorize Theme.instance
    Settings[:print_css] = params.dig(:print_style, :css).to_s
    redirect_to theme_path, notice: "Print style was successfully updated.", status: :see_other
  end
end
