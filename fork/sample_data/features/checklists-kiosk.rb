# Builds on the "Trip Eligibility" checklist (feature/checklists sample data,
# with feature/checklists-person-fields' "Photo release" item). That item is
# marked to list at the time kiosk while it isn't done. Scan Kate's card (her
# photo release is set to no): a "You still need" box lists "Photo release".
# Chloe's release is yes, so her card shows nothing extra. Managers' cards
# never show the box. Each uses her scan card, or gets one outside the base
# range (10000001-10000032) if she has none.
Hbr::SampleData.people([])

Hbr::SampleData.feature "feature/checklists-kiosk" do |s|
  s.enable_feature :checklists
  checklist = Checklist.find_by!(title: "Trip Eligibility")
  photo = checklist.checklist_items.find_by!(label: "Photo release")
  photo.update!(show_on_kiosk: true) unless photo.show_on_kiosk?

  Checklists::Refresher.new(checklist.reload, silent: true).call
  kate = s.person("Kate")
  chloe = s.person("Chloe")
  cards = { kate => "10000111", chloe => "10000112" }.to_h do |person, value|
    [ person, Token.find_by(tokenable: person) || Token.find_or_create_by!(value: value) { |token| token.tokenable = person } ]
  end
  s.report "Photo release lists at the time kiosk while not done: scan card #{cards[kate].value} (Kate; lists it), #{cards[chloe].value} (Chloe; done)"
  s.expect("the photo release item is marked for the kiosk") { photo.reload.show_on_kiosk? }
  s.expect("Kate's card lists the photo release") { Checklists::KioskLines.for(kate).include?("Photo release") }
  s.expect("Chloe's card doesn't list it") { Checklists::KioskLines.for(chloe).exclude?("Photo release") }
end
