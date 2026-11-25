# Machines (places whose type holds installed parts: the group's Robots, Practice bases, whatever its
# place types are), as the machine pages list them
# (Inventory::MachinesController#index: authorize :inventory, :use?; policy_scope(Location) of the
# type, active first, by full name), each with the units installed on it as its page lists them
# (policy_scope(ItemUnit), active, by code; a unit inside one the viewer can't see is listed at the
# top) and those whose condition is flagged (a condition that needs attention). Needs the inventory feature.
class Mcp::Tools::ListMachines < Mcp::Tool
  include Mcp::InventoryRecords

  tool_name "list_machines"
  description "Places parts get installed on: every place whose type holds installed parts (the types are listed in types), " \
    "with the parts installed on each (by code, with condition and what each is inside) and how many need repair. " \
    "Filters: type_id (a place type's ID or name), team_id."
  scope :read
  feature :inventory
  input_schema(
    properties: {
      type_id: { type: "string", description: "Only places of this type (plty_, or its name)" },
      team_id: { type: "string", description: "Only this team's (tm_)" }
    }
  )
  output_schema(
    type: "object",
    properties: {
      types: { type: "array", items: Mcp::InventoryRecords::TYPE_SCHEMA },
      machines: {
        type: "array",
        items: {
          type: "object",
          properties: Mcp::InventoryRecords::PLACE_SCHEMA[:properties].merge(
            team: Mcp::Tool::REF_SCHEMA, active: { type: "boolean" }, units: { type: "array", items: Mcp::InventoryRecords::UNIT_REF_SCHEMA },
            flagged: { type: "integer" }
          ),
          required: Mcp::InventoryRecords::PLACE_SCHEMA[:required] + %w[team active units flagged]
        }
      }
    },
    required: %w[types machines]
  )

  def call(type_id: nil, team_id: nil)
    ctx.authorize!(:inventory, :use?)
    types = LocationType.installable.to_a
    only = type_id && types.find { |type| type.id == list_row(LocationType, type_id, "place type").id }
    invalid_argument!("#{type_id} isn't a type parts get installed on") if type_id && only.nil?
    machines = ctx.policy_scope(Location).where(location_type_id: (only ? [ only ] : types).map(&:id)).includes(:parent, :team, :location_type)
    machines = machines.where(team_id: ctx.find(Team, team_id).id) if team_id
    machines = machines.sort_by { |machine| [ machine.active? ? 0 : 1, machine.full_name ] }
    units = ctx.policy_scope(ItemUnit).active.where(location_id: machines.map(&:id)).includes(:item, :installed_in, :unit_condition).order(:code).to_a
    by_machine = units.group_by(&:location_id)
    {
      types: types.map { |type| type_json(type) },
      machines: machines.map do |machine|
        installed = by_machine.fetch(machine.id, [])
        seen = installed.to_set(&:id)
        place_json(machine).merge(
          team: team_json(machine.team),
          active: machine.active?,
          units: installed.map do |unit|
            json = unit_ref_json(unit)
            json[:installed_in] = nil unless seen.include?(unit.installed_in_id)
            json
          end,
          flagged: installed.count(&:flagged?)
        )
      end
    }
  end
end
