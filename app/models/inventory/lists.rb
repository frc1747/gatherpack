# The lists inventory groups manage on Setup (managed lists): place types,
# stock units, part conditions and reading types. Their starting rows come
# from the migrations. In a database made from the schema (a fresh install,
# tests) the code that first needs a list fills it (seed!: the default
# place type, stock unit or condition, the menu, the readings screen).
# Every default row has a key, so it can be retired but not deleted or
# merged away, and a list once filled never empties again: a deleted
# default can't come back.
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
          { name: "Hours", plural: "Hours", key: "hours", unit_label: "h" },
          { name: "Cycles", plural: "Cycles", key: "cycles" },
          { name: "Volts", plural: "Volts", key: "volts", unit_label: "V" }
        ]
      }
    end

    def seed_defaults!
      defaults.each { |model, rows| model.seed_defaults!(rows) }
    end

    # Fills one list with its defaults when it's empty.
    def seed!(model)
      model.seed_defaults!(defaults.fetch(model))
    end
  end
end
