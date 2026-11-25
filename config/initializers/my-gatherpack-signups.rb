# Puts a person's sign-ups on the My GatherPack home page and opens Manage to
# sheet organizers. The core registers sections from here, so it holds no
# sign-up code.
Rails.application.config.to_prepare do
  MyGatherpack.register_section(:signups, partial: "my_gatherpack/signup_row", column: :coming_up, position: 20,
    enabled: -> { GatherPack::Features.enabled?(:signups) }, items: -> { my_gatherpack_signup_items })

  MyGatherpack::Menu.register_manager_check(:signup_organizer, paths: [ :signup_sheets_path ]) do |person|
    GatherPack::Features.enabled?(:signups) && SignupSheet.organizer_team_ids(person).any?
  end
end
