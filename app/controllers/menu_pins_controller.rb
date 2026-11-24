# Pins and unpins sidebar items for the signed-in person. The key is only
# saved, never followed: the menu shows a pin only for an item it would show
# this person anyway.
class MenuPinsController < InternalController
  before_action :check_for_feature
  skip_after_action :verify_pundit_authorization

  # POST /menu_pins
  def create
    pins.find_or_create_by!(path_key: params.require(:path_key))
    render json: { pinned: true }, status: :created
  end

  # DELETE /menu_pins/:id, where the id is the pin's path key.
  def destroy
    pins.where(path_key: params[:id]).delete_all
    render json: { pinned: false }
  end

  private

  def pins
    MenuPin.where(user: current_user)
  end

  def check_for_feature
    head :not_found unless MyGatherpack.enabled?
  end
end
