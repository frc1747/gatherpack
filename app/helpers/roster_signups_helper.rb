module RosterSignupsHelper
  # "Fulfilled" and "No-show" read "Brought" and "Not brought" for items.
  def roster_status_label(signup)
    if signup.signup_position.items? && (signup.fulfilled? || signup.no_show?)
      signup.fulfilled? ? "Brought" : "Not brought"
    else
      { "active" => "Signed up", "cancelled" => "Cancelled", "fulfilled" => "Fulfilled", "no_show" => "No-show" }.fetch(signup.status)
    end
  end

  # "3 pizzas" for items; nothing for people.
  def roster_amount(signup)
    position = signup.signup_position
    return unless position.items?

    "#{signup.quantity} #{signup.quantity == 1 ? position.unit_label.singularize : position.unit_label}"
  end

  # "Game Day, Sat Oct 24 10:00 AM: Cashier"
  def roster_slot_label(slot)
    "#{slot.event.name}, #{slot.event.start_time.strftime("%a %b %-d %-l:%M %p")}: #{slot.signup_position.name}"
  end
end
