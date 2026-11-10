# Nothing to add: this is infrastructure. It lets features register their own
# settings and hook events, and the sign-ups sample data uses both (its
# Sign-up Sheet Organizers setting and its Hook events).
Hbr::SampleData.feature "feature/extension-registries" do |s|
  s.note "no data needed (the sign-ups data exercises the registered setting and hook events)"
end
