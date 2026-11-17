# The jobs dashboard (/jobs) runs on JobsDashboardController, which only
# lets admins in, rather than on ApplicationController, which lets in
# anyone signed in.
MissionControl::Jobs.base_controller_class = "JobsDashboardController"
