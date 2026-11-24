# Turns the menu on. Everyone it needs to show is already in the base and
# person-fields data: Ella (member@), Mara (manager@), Adam (admin@), Paula
# (parent1@, two wards) and Ben (clocked in). The Forms creator and the
# partly-met commitment need the connector branches, which add their own.
#
# Two report Pages ticked "Show in the menu" fill the sidebar's Reports group:
# Ella sees Volunteer Hours; Mara (a Programs leader) also sees Programs
# Roster; Adam sees both. Pins are personal and start empty.
Hbr::SampleData.feature "feature/my-gatherpack" do |s|
  s.enable_feature :my_gatherpack

  s.upsert!(Page, { title: "Volunteer Hours" },
    content: "# Volunteer Hours\n\nHours logged this season, by team.",
    viewer: "user", editor: "admin", team: s.team(:root), show_in_menu: true)
  s.upsert!(Page, { title: "Programs Roster" },
    content: "# Programs Roster\n\nWho is on each Programs crew, for its leaders.",
    viewer: "manager", editor: "manager", team: s.team(:programs), show_in_menu: true)

  s.note "Sign in as member@, manager@ or admin@ to compare the menu"
  s.note "Reports in the sidebar: member@ sees Volunteer Hours; manager@ also sees Programs Roster"
end
