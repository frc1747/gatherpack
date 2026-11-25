class SignupSheetEventPolicy < SignupSheetPartPolicy
  # Organizers change the name, place and time only of events their sheet
  # made (Add dates). Events a manager made and attached stay with
  # EventPolicy.
  def update?
    manage? && record.created_by_sheet?
  end
end
