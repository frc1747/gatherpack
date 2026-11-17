# Finds the unit someone typed or scanned: a unit's code, its serial
# number, or the URL on its label. Only units the viewer sees are looked
# at. Codes are unique within a team, not across teams, so when several
# match, the one on the given team wins; if that still leaves more than
# one, the lookup is refused rather than guessing.
module Inventory
  module UnitLookup
    UNIT_URL = %r{/inventory/units/([^/?#\s]+)}

    private

    # The unit for input, or raises Inventory::Refused. team_id is the team
    # to prefer when a code is used by more than one team.
    def unit_from_code(input, team_id: nil)
      input = input.to_s.strip
      raise Inventory::Refused, "Type or scan the part's code" if input.empty?

      units = policy_scope(ItemUnit).active.includes(:item)
      if (match = UNIT_URL.match(input))
        return units.find(match[1])
      end

      matches = units.where("LOWER(item_units.code) = ?", input.downcase).to_a
      matches = units.where("LOWER(item_units.serial_number) = ?", input.downcase).to_a if matches.empty?
      raise Inventory::Refused, "No part has the code #{input}" if matches.empty?

      preferred = matches.select { |unit| unit.item.team_id == team_id }
      matches = preferred if preferred.any?
      return matches.first if matches.one?

      raise Inventory::Refused, "#{matches.size} parts have the code #{input}: scan the label of the one you mean"
    rescue ActiveRecord::RecordNotFound
      raise Inventory::Refused, "That label isn't for a part you can see"
    end
  end
end
