# Machines (places parts get installed on; the group names them on Inventory setup), as the
# Machines page lists them
# (Inventory::MachinesController#index: authorize :inventory, :use?; policy_scope(Location).machine,
# active first, by full name), each with the units installed on it as its page lists them
# (policy_scope(ItemUnit), active, by code; a unit inside one the viewer can't see is listed at the
# top) and those whose condition is flagged (Needs repair or Broken). Needs the inventory feature.
class Mcp::Tools::ListMachines < Mcp::Tool
  include Mcp::InventoryRecords

  tool_name "list_machines"
  description "Places parts get installed on (kind machine; the group may call them something else, given in called), " \
    "with the parts installed on each (by code, with condition and what each is inside) and how many need repair. " \
    "Refused when the group has turned them off. Filter: team_id."
  scope :read
  feature :inventory
  input_schema(
    properties: {
      team_id: { type: "string", description: "Only this team's (tm_)" }
    }
  )
  output_schema(
    type: "object",
    properties: {
      called: { type: "object", properties: { one: { type: "string" }, many: { type: "string" } } },
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
    required: %w[machines]
  )

  def call(team_id: nil)
    ctx.authorize!(:inventory, :use?)
    words = Inventory.respond_to?(:machine_word)
    invalid_argument!("#{Inventory.machine_word(count: :many, capitalize: true)} are turned off") if words && !Inventory.machines?
    machines = ctx.policy_scope(Location).machine.includes(:parent, :team)
    machines = machines.where(team_id: ctx.find(Team, team_id).id) if team_id
    machines = machines.sort_by { |machine| [ machine.active? ? 0 : 1, machine.full_name ] }
    units = ctx.policy_scope(ItemUnit).active.where(location_id: machines.map(&:id)).includes(:item, :installed_in).order(:code).to_a
    by_machine = units.group_by(&:location_id)
    {
      called: { one: words ? Inventory.machine_word(capitalize: true) : "Machine", many: words ? Inventory.machine_word(count: :many, capitalize: true) : "Machines" },
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
