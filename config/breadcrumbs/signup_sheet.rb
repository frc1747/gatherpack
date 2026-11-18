crumb :signup_sheets do
  link "Sign-ups", signup_sheets_path
end

crumb :signup_sheet do |signup_sheet|
  link signup_sheet.new_record? ? "New sign-up sheet" : signup_sheet.identifier_name, signup_sheet
  parent :signup_sheets
end
