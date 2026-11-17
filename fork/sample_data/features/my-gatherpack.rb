# Turns the menu on. Everyone it needs to show is already in the base and
# person-fields data: Ella (member@), Mara (manager@), Adam (admin@), Paula
# (parent1@, two wards) and Ben (clocked in). The Forms creator and the
# partly-met commitment need the connector branches, which add their own.
Hbr::SampleData.feature "feature/my-gatherpack" do |s|
  s.enable_feature :my_gatherpack
  s.note "Sign in as member@, manager@ or admin@ to compare the menu"
end
