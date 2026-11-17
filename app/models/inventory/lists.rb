# The lists inventory groups manage on Setup (managed lists): place types,
# stock units, part conditions and reading types. Their starting rows come
# from the migrations; seed_defaults! puts them into a database made from
# the schema instead (a fresh install, tests), and does nothing to a list
# that has rows.
module Inventory
  module Lists
    module_function

    def defaults
      {
        LocationType => [
          { name: "Storage", plural: "Storage places", key: "storage", holds_stock: true, holds_installed_parts: false },
          { name: "Machine", plural: "Machines", key: "machine", holds_stock: false, holds_installed_parts: true }
        ],
        StockUnit => [
          { name: "each", plural: "each", key: "each", default: true },
          { name: "box", plural: "boxes" },
          { name: "pack", plural: "packs" },
          { name: "roll", plural: "rolls" },
          { name: "foot", plural: "feet" },
          { name: "set", plural: "sets" }
        ],
        UnitCondition => [
          { name: "New", key: "new" },
          { name: "Good", key: "good" },
          { name: "Worn", key: "worn" },
          { name: "Needs repair", key: "needs_repair", needs_attention: true },
          { name: "Broken", key: "broken", needs_attention: true },
          { name: "Retired", key: "retired", out_of_service: true }
        ],
        ReadingType => [
          { name: "Hours", plural: "Hours", unit_label: "h" },
          { name: "Cycles", plural: "Cycles" },
          { name: "Volts", plural: "Volts", unit_label: "V" }
        ]
      }
    end

    def seed_defaults!
      defaults.each { |model, rows| model.seed_defaults!(rows) }
    end
  end
end
