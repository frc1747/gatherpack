# Pins and unpins sidebar items for the signed-in person. The key is only
# saved, never followed: the menu shows a pin only for an item it would show
# this person anyway. Each answer redraws just the sidebar's menu, so the page
# around it, and anything typed on it, is kept.
class MenuPinsController < InternalController
  before_action :check_for_feature

  # POST /menu_pins
  def create
    pin = policy_scope(MenuPin).find_or_initialize_by(path_key: params.require(:path_key))
    authorize pin
    pin.save! if pin.new_record?
    render_menu
  end

  # DELETE /menu_pins/:id, where the id is the pin's path key.
  def destroy
    pin = authorize policy_scope(MenuPin).find_by!(path_key: params[:id])
    pin.destroy!
    render_menu
  end

  private

  # The menu marks the page it's drawn on as active, so it's drawn for the
  # page the pin was clicked on (+from+, a local path), not for this request.
  def render_menu
    from = params[:from].to_s
    request.path_info = from if from.match?(%r{\A/(?![/\\])})
    render turbo_stream: turbo_stream.update("mg-menu", partial: "my_gatherpack/menu")
  end

  def check_for_feature
    head :not_found unless MyGatherpack.enabled?
  end
end
