# A "My sign-ups and commitments" widget for everyone signed in, at the top
# of the right column. Its ERB is one line; the partial hides the card for
# anyone with no upcoming sign-ups and no commitments. Paula (parent1) sees
# her Fall Fair Setup place on Kate's behalf and Kate's family's Youth Family
# Shifts.
Hbr::SampleData.feature "feature/signups-widget" do |s|
  s.enable_feature :widgets

  s.upsert!(Widget, { title: "My sign-ups and commitments" },
    placement: "right", position: -1, viewer: "user", team: nil, dynamic: true, enabled: true,
    content: %(<%= render "signups_summaries/summary" %>))

  paula = SignupsSummary.new(s.login(:parent1).user)
  s.report "My sign-ups and commitments widget"
  s.expect("Paula sees her Fall Fair Setup place on Kate's behalf") do
    paula.signups.any? { |signup| signup.event.name == "Fall Fair Setup" && signup.on_behalf_of == s.person("Kate") }
  end
  s.expect("Paula sees Kate's family's Youth Family Shifts") do
    paula.commitments.any? { |item| item.progress.commitment.title == "Youth Family Shifts" }
  end
end
