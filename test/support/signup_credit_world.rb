require_relative "commitments_world"

# The commitments world (see CommitmentsWorld) with a sign-up sheet on it:
# Snack Stand belongs to Club, is run by organizer, and has a Cashier
# (people) and a Main dish (items) position. Its events are added per test.
module SignupCreditWorld
  include CommitmentsWorld

  def build_signup_credit_world
    build_commitments_world
    @sheet = SignupSheet.create!(title: "Snack Stand", team: @club, status: :open, created_by: person(:organizer))
    @cashier = @sheet.signup_positions.create!(name: "Cashier", kind: :people, capacity: 4)
    @dish = @sheet.signup_positions.create!(name: "Main dish", kind: :items, unit: "dishes")
  end

  def add_sheet_event(name, start_time, team: @club)
    event = create_world_event(name, start_time, team: team)
    @sheet.signup_sheet_events.create!(event: event)
    event
  end

  def sign_up(name, position, event, status: :active, on_behalf_of: nil)
    Signup.create!(signup_slot: position.signup_slots.find_by!(event: event), person: person(name), signed_up_by: person(name),
      on_behalf_of: on_behalf_of && person(on_behalf_of), status: status, quantity: position.items? ? 3 : nil)
  end
end
