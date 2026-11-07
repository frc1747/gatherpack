# The attendance item kind and excusing one meeting (feature/checklists-
# attendance). Registers only when the checklists core is present.
Rails.application.config.to_prepare do
  next unless defined?(Checklists) && Checklists.respond_to?(:register_item_kind)

  Checklists.register_item_kind(:attendance, Checklists::Kinds::Attendance)
  ChecklistExcusesController.include(ChecklistMeetingExcuses) unless ChecklistExcusesController < ChecklistMeetingExcuses
  unless Checklists::Copier < Checklists::Kinds::Attendance::CopiesRuleDates
    Checklists::Copier.prepend(Checklists::Kinds::Attendance::CopiesRuleDates)
  end
end
