# Forms on the My GatherPack home page. The core knows nothing of forms; this
# adds a to-do section, the Manage check for a Forms creator and the phone form styles.
Rails.application.config.to_prepare do
  MyGatherpack.register_section(:forms, partial: "my_gatherpack/todo_row", column: :todo, position: 10,
    enabled: -> { GatherPack::Features.enabled?(:forms) }, items: -> { my_gatherpack_form_items })

  # Phone styles for filling out a form, by the form's own ids, so no view is overridden.
  GatherPack::SidebarSlots.register(:my_gatherpack_phone_form, partial: "my_gatherpack/phone_form_styles", position: 900,
    visible: ->(_view) { MyGatherpack.enabled? })

  # A creator who manages no team still gets Manage, for the forms they run.
  MyGatherpack::Menu.register_manager_check(:forms, paths: [ :forms_path ]) { |person| Form.creator?(person) }
end
