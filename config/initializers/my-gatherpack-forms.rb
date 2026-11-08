# Forms on the My GatherPack home page. The core knows nothing of forms; this
# adds a to-do section and the Manage check for a Forms creator.
Rails.application.config.to_prepare do
  MyGatherpack.register_section(:forms, partial: "my_gatherpack/todo_row", column: :todo, position: 10,
    enabled: -> { GatherPack::Features.enabled?(:forms) }, items: -> { my_gatherpack_form_items })

  # A creator who manages no team still gets Manage, for the forms they run.
  MyGatherpack::Menu.register_manager_check(:forms, paths: [ :forms_path ]) { |person| Form.creator?(person) }
end
