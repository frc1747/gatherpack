# Checklists on the My GatherPack home page and menu. Lives here so neither
# feature needs the other's code.
Rails.application.config.to_prepare do
  next unless defined?(MyGatherpack) && MyGatherpack.respond_to?(:register_section) && defined?(Checklists)

  MyGatherpack.register_section(:checklists_todo, partial: "my_gatherpack/todo_row", column: :todo, position: 20,
    enabled: -> { Checklists.enabled? }, items: -> { my_gatherpack_checklist_items })
  MyGatherpack.register_section(:checklists_season, partial: "my_gatherpack/checklists_season", column: :side, position: 20,
    enabled: -> { Checklists.enabled? })

  # Someone who organizes checklists without managing a team still gets Manage.
  MyGatherpack::Menu.singleton_class.prepend(MyGatherpack::ChecklistsMenuTable)
  MyGatherpack::Menu.table = MyGatherpack::Menu.table
  MyGatherpack::Menu.register_manager_check(:checklists, paths: [ :checklists_path ]) do |person|
    Checklists.enabled? && Checklist.creatable_team_ids(person).any?
  end
end
