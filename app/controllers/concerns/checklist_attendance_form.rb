# Lets the attendance item's period lists offer only the checklist's own
# periods (its team, the teams below it, and periods on no team). Included
# in ChecklistItemsController by config/initializers/checklists_attendance.rb
# until item kinds can draw their own form section.
module ChecklistAttendanceForm
  extend ActiveSupport::Concern

  included do
    before_action :scope_attendance_periods
  end

  private

  def scope_attendance_periods
    Checklists::Kinds::Attendance::Form.checklist = @checklist
  end
end
