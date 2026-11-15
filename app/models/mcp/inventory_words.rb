# The inventory pages' own words for one viewer: a unit's history lines, its readings and the
# actions its page offers, and places' full names. It includes the helper the unit and machine
# pages use (Inventory::UnitsHelper), so a tool says what the page says. policy is the viewer's,
# as the views' policy is.
class Mcp::InventoryWords
  include Inventory::UnitsHelper

  def initialize(user)
    @user = user
  end

  def policy(record)
    Pundit.policy!(@user, record)
  end
end
