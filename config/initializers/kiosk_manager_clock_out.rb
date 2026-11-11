# Kiosk: let managers clock out the people they manage (see
# TimeKiosk::ManagerClockOut). Off by default: the kiosk then clocks out only
# the periods on the teams a manager manages, as upstream's does.
Rails.application.config.to_prepare do
  Settings.register(TimeKiosk::ManagerClockOut::SETTING, :boolean, "Kiosk: Managers Clock Out the People They Manage", "false", "Time Clock",
    "In the kiosk's Manager window, a team manager can clock out anyone in the teams they manage (including teams below them), whatever time period they're clocked in to. Off: only the periods that belong to the teams they manage.")
end
