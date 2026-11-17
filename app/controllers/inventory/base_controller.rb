# Base of every inventory controller: turns requests away while the feature
# is off, fills any empty inventory list with its starting rows, and shows a
# refused domain action as a flash.
module Inventory
  class BaseController < InternalController
    before_action :require_feature
    before_action { Inventory::Lists.seed_defaults! }
    helper_method :current_person, :managed_teams

    rescue_from Inventory::Refused do |error|
      redirect_back fallback_location: inventory_root_path, alert: error.message
    end

    private

    def require_feature
      redirect_to root_path, notice: "Inventory is turned off" unless Inventory.enabled?
    end

    def current_person
      current_user&.person
    end

    def access
      Inventory::Access.for(current_person)
    end

    # Teams whose items and places the person manages, for team pickers.
    def managed_teams
      access.admin? ? Team.order(:name) : Team.where(id: access.managed_team_ids.to_a).order(:name)
    end

    # Where to go after a form: the page it was opened from, when that's an
    # inventory page, else the fallback.
    def return_path(fallback)
      path = params[:return_to].to_s
      path.start_with?("/inventory") && !path.start_with?("//") ? path : fallback
    end

    # { move_group_id => { id => row } } for the moves among these
    # movements, so history shows each move as one line.
    def move_partners(movements)
      groups = movements.filter_map(&:move_group_id)
      return {} if groups.empty?

      StockMovement.where(move_group_id: groups).includes(:location).group_by(&:move_group_id)
        .transform_values { |rows| rows.index_by(&:id) }
    end

    # The item's default place (home, or the only place with stock) when the
    # person can see it, else nil: a member may not see the home place of an
    # item shared from a team above.
    def visible_default_location(item)
      place = item.default_location
      place if place && policy_scope(Location).exists?(id: place.id)
    end

    # Remembers a change just recorded, so the next page offers Undo.
    def offer_undo(movement)
      session[:inventory_undo] = movement.id
    end
  end
end
