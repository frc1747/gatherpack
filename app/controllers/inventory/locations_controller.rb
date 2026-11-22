# Places: the tree, the place page (phone-first: what's here, with Used and
# Count on each row), Count this place, and editing for inventory managers
# (spec §3.9).
module Inventory
  class LocationsController < BaseController
    before_action :set_location, only: %i[show edit update destroy count save_count]

    # GET /inventory/places
    def index
      authorize Location
      @locations = policy_scope(Location).includes(:location_type).ordered.to_a
      @children = @locations.group_by(&:parent_id)
      ids = @locations.to_set(&:id)
      @roots = @locations.select { |location| location.parent_id.nil? || !ids.include?(location.parent_id) }
      @needs_count = StockLevel.where("quantity < 0").distinct.pluck(:location_id).to_set
    end

    # GET /inventory/places/1
    def show
      @levels = stock_here.to_a
      @totals = Inventory::Stock.totals(@levels.map(&:item))
      @children = policy_scope(@location.children).to_a
      @countable = countable_levels.any?
    end

    # GET /inventory/places/new
    def new
      parent = params[:parent_id].presence && policy_scope(Location).find(params[:parent_id])
      @location = authorize Location.new(parent: parent, team_id: parent&.team_id || managed_teams.first&.id)
    end

    # GET /inventory/places/1/edit
    def edit
    end

    # POST /inventory/places
    def create
      @location = authorize Location.new(location_params)

      if @location.save
        redirect_to inventory_location_path(@location), notice: "#{@location.name} was added."
      else
        render :new, status: :unprocessable_entity
      end
    end

    # PATCH/PUT /inventory/places/1
    def update
      @location.assign_attributes(location_params)
      authorize @location

      if @location.save
        redirect_to inventory_location_path(@location), notice: "#{@location.name} was saved.", status: :see_other
      else
        render :edit, status: :unprocessable_entity
      end
    end

    # DELETE /inventory/places/1
    def destroy
      parent = @location.parent
      @location.destroy!
      redirect_to parent ? inventory_location_path(parent) : inventory_locations_path,
        notice: "#{@location.name} was deleted.", status: :see_other
    end

    # GET /inventory/places/1/count
    def count
      @levels = countable_levels
      redirect_to inventory_location_path(@location), alert: "There's nothing here you can count." if @levels.empty?
    end

    # POST /inventory/places/1/count
    def save_count
      allowed = countable_levels.index_by { |level| level.item.id }
      counts = params.fetch(:counts, {}).to_unsafe_h.select { |_id, value| value.to_s.strip.present? }
      saved = 0
      differences = 0
      problems = []
      counts.each do |item_id, value|
        level = allowed[item_id]
        next if level.nil?

        movement = StockMovement.record!(kind: :counted, item: level.item, location: @location, quantity: value,
          person: current_person)
        saved += 1
        differences += 1 unless movement.quantity.zero?
      rescue Inventory::Refused => error
        problems << "#{level.item.name}: #{error.message}"
      end

      notice = "Saved #{helpers.pluralize(saved, "count")}" \
        "#{saved.positive? ? " (#{differences.zero? ? "no differences" : helpers.pluralize(differences, "difference")})" : ""}."
      redirect_to inventory_location_path(@location), notice: notice, alert: problems.to_sentence.presence, status: :see_other
    end

    private

    def set_location
      # Counting is checked per item (countable_levels); the place need only be seen.
      query = action_name.in?(%w[count save_count]) ? :show? : nil
      @location = authorize policy_scope(Location).find(params[:id]), query
    end

    # Levels here for active items the person sees, with the place as home
    # for items kept here that have none yet, by item name.
    def stock_here
      items = policy_scope(Item).where(active: true)
      levels = @location.stock_levels.where(item_id: items.select(:id)).where.not(quantity: 0).includes(item: :item_sources).to_a
      homed = items.where(home_location_id: @location.id, tracked: false).where.not(id: levels.map(&:item_id)).includes(:item_sources)
      (levels + homed.map { |item| StockLevel.new(item: item, location: @location, quantity: 0) }).sort_by { |level| level.item.name.downcase }
    end

    # What this person may count here.
    def countable_levels
      @countable_levels ||= stock_here.select do |level|
        !level.item.tracked? && access.may_record?("counted", level.item, @location)
      end
    end

    def location_params
      permitted = params.require(:location).permit(:team_id, :parent_id, :name, :code, :location_type_id, :note, :position, :active)
      if permitted[:parent_id].present? && !policy_scope(Location).exists?(id: permitted[:parent_id])
        permitted[:parent_id] = nil
      end
      # A place inside another takes the parent's team.
      permitted.delete(:team_id) if permitted[:parent_id].present?
      permitted
    end
  end
end
