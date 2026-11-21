class PrintStylesController < ApplicationController
  before_action :check_for_admin

  def update
    Settings[:print_css] = params.dig(:print_style, :css).to_s
    redirect_to theme_path, notice: "Print style was successfully updated.", status: :see_other
  end
end
