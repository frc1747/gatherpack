crumb :forms do
  link "Forms", forms_path
  parent :root
end

crumb :form do |form|
  link form.new_record? ? "New form" : form.identifier_name, form.new_record? ? new_form_path : form_path(form)
  parent :forms
end

crumb :edit_form do |form|
  link "Edit", edit_form_path(form)
  parent :form, form
end

crumb :form_question do |question|
  link question.new_record? ? "New question" : (question.label.presence || question.key), question.new_record? ? new_form_question_path(question.form) : edit_form_question_path(question.form, question)
  parent :edit_form, question.form
end

crumb :form_results do |form|
  link "Results", results_form_path(form)
  parent :form, form
end

crumb :form_tally do |form|
  link "Tally", tally_form_path(form)
  parent :form, form
end

crumb :form_preview do |form|
  link "Preview as…", preview_form_path(form)
  parent :form, form
end

crumb :form_response do |response|
  link "#{response.form.title}: #{response.subject.identifier_name}", form_response_path(response.form, response.subject_id)
  parent :forms
end

crumb :edit_form_response do |response|
  link "Fill in", edit_form_response_path(response.form, response.subject_id)
  parent :form_response, response
end
