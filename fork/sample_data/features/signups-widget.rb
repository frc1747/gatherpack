# The "My Sign-ups and Commitments" card at the top of the dashboard's right
# column needs no data of its own; it's hidden for anyone with no upcoming
# sign-ups and no commitments. Ella (member) sees the Spring Workday Greeter
# place Ben works on her behalf. Paula (parent1) sees Kate's family's Youth
# Family Shifts, but not her Fall Fair Setup place for Kate: she isn't in
# that sheet's audience, and the card only lists sign-ups on sheets the
# person may see.
Hbr::SampleData.feature "feature/signups-widget" do |s|
  ella = SignupsSummary.new(s.login(:member).user)
  paula = SignupsSummary.new(s.login(:parent1).user)
  s.report "My Sign-ups and Commitments card for Ella (member@) and Paula (parent1@)"
  s.expect("Ella sees the Spring Workday place Ben works on her behalf") do
    ella.signups.any? { |signup| signup.event.name == "Spring Workday" && signup.person == s.person("Ben") && signup.on_behalf_of == s.person("Ella") }
  end
  s.expect("Paula sees Kate's family's Youth Family Shifts") do
    paula.commitments.any? { |item| item.progress.commitment.title == "Youth Family Shifts" }
  end
  s.expect("Paula doesn't see her place on a sheet outside her audience") do
    paula.signups.none? { |signup| signup.event.name == "Fall Fair Setup" }
  end
end
