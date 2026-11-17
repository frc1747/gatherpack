# Places the viewer can see, as Inventory → Places lists them (Inventory::LocationsController#index:
# authorize index?, which is inventory_users; policy_scope(Location), in the tree's order), with the
# full path, code and type. items counts the active items the viewer sees with stock there (as the
# place's page lists them), and needs_count marks a place with stock recorded below zero. parent_id
# lists the places directly inside one place; team_id one team's places. Needs the inventory
# feature.
class Mcp::Tools::ListLocations < Mcp::Tool
  include Mcp::InventoryRecords

  tool_name "list_locations"
  description "Inventory places you can see (shelves, cabinets, bins, and the places parts get installed on), with full path, code, type (with holds_stock and " \
    "holds_installed_parts), how many items have stock there and whether one needs a count. Filters: parent_id (places directly inside one), team_id."
  scope :read
  feature :inventory
  input_schema(
    properties: {
      parent_id: { type: "string", description: "Only places directly inside this one (loc_)" },
      type_id: { type: "string", description: "Only places of this type (plty_, or its name)" },
      team_id: { type: "string", description: "Only this team's places (tm_)" },
      limit: limit_property
    }
  )
  output_schema(
    type: "object",
    properties: {
      items: {
        type: "array",
        items: {
          type: "object",
          properties: Mcp::InventoryRecords::PLACE_SCHEMA[:properties].merge(
            code: { type: %w[string null] }, team: Mcp::Tool::REF_SCHEMA, active: { type: "boolean" },
            parent_id: { type: %w[string null] }, items: { type: "integer" }, needs_count: { type: "boolean" }
          ),
          required: Mcp::InventoryRecords::PLACE_SCHEMA[:required] + %w[code team active parent_id items needs_count]
        }
      },
      truncated: { type: "boolean" }
    },
    required: %w[items truncated]
  )

  def call(parent_id: nil, type_id: nil, team_id: nil, limit: DEFAULT_LIMIT)
    ctx.authorize!(Location, :index?)
    places = ctx.policy_scope(Location).includes(:team, :parent, :location_type).order(:position, :name, :id)
    places = places.where(parent_id: find_place(parent_id).id) if parent_id
    places = places.where(location_type_id: list_row(LocationType, type_id, "place type").id) if type_id
    places = places.where(team_id: ctx.find(Team, team_id).id) if team_id
    page = list(places, limit: limit) { |place| place }
    page.merge(items: places_json(page[:items]))
  end

  private

  def places_json(places)
    ids = places.map(&:id)
    visible_items = ctx.policy_scope(Item).where(active: true).select(:id)
    counts = StockLevel.where(location_id: ids, item_id: visible_items).where.not(quantity: 0).group(:location_id).count
    below_zero = StockLevel.where(location_id: ids).where("quantity < 0").distinct.pluck(:location_id).to_set
    names = inventory_words.inventory_full_names(places)
    places.map do |place|
      place_json(place, names).merge(
        code: place.code.presence,
        team: team_json(place.team),
        active: place.active?,
        parent_id: place.parent&.neat_id,
        items: counts[place.id].to_i,
        needs_count: below_zero.include?(place.id)
      )
    end
  end
end
