# The home page's forms to-dos. Each row comes from the helpers the Forms page
# uses (forms_to_complete, leader_todos, form_entry_path), so a row can't offer
# anything that page doesn't.
module MyGatherpackFormsHelper
  def my_gatherpack_form_items
    person = current_user.person
    entries = forms_to_complete(person).map { |entry| my_gatherpack_form_entry_item(entry, person) }
    leaders = leader_todos(person).map { |todo| my_gatherpack_leader_todo_item(todo) }
    entries + leaders
  end

  private

  def my_gatherpack_form_entry_item(entry, person)
    ward = entry.subject unless entry.subject.id == person.id
    due = form_due(entry.form)
    MyGatherpack::Item.new(
      title: entry.form.title,
      detail: ward ? "#{due} · You're their guardian" : due,
      at: entry.form.closes_at,
      path: form_entry_path(entry),
      action: entry.needs_viewer_signature? ? "Sign" : "Fill out",
      icon: "file-signature",
      ward: ward && (ward.first_name.presence || ward.identifier_name)
    )
  end

  def my_gatherpack_leader_todo_item(todo)
    names = todo.people.map(&:identifier_name)
    MyGatherpack::Item.new(
      title: todo.form.title,
      detail: "Waiting on you: #{names.first(2).to_sentence}#{" and #{names.size - 2} more" if names.size > 2}",
      at: todo.form.closes_at,
      path: form_path(todo.form, status: "waiting"),
      action: "Open",
      icon: "file-signature"
    )
  end
end
