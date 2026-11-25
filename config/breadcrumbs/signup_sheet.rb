crumb :signup_sheets do
  link "Sign-ups", signup_sheets_path
end

crumb :signup_sheet do |signup_sheet|
  link signup_sheet.new_record? ? "New sign-up sheet" : signup_sheet.identifier_name, signup_sheet
  parent :signup_sheets
end

crumb :edit_signup_sheet do |signup_sheet|
  link "Edit", edit_signup_sheet_path(signup_sheet, tab: "details")
  parent :signup_sheet, signup_sheet
end

crumb :signup_sheet_roster do |signup_sheet|
  link "Roster", roster_signup_sheet_path(signup_sheet)
  parent :signup_sheet, signup_sheet
end
