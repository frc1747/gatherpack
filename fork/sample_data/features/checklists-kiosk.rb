# Builds on the "Joining Northwind" checklist (feature/intake-checklist sample
# data). The "Family agreement" item is marked to list at the time kiosk while
# it isn't done. Ivy Reyes and Rosa Vale have no scan card in the base layer,
# so this layer gives each one (outside the base range 10000001-10000032).
# Scan Ivy's card (she is in Junior Crew and hasn't confirmed the agreement):
# a "You still need" box lists "Family agreement". Rosa has confirmed hers, so
# her card shows nothing extra. Managers' cards never show the box.
Hbr::SampleData.people([])

Hbr::SampleData.feature "feature/checklists-kiosk" do |s|
  s.enable_feature :checklists
  checklist = Checklist.find_by!(title: "Joining Northwind")
  agreement = checklist.checklist_items.find_by!(label: "Family agreement")
  agreement.update!(show_on_kiosk: true) unless agreement.show_on_kiosk?

  Checklists::Refresher.new(checklist.reload, silent: true).call
  ivy = Person.find_by!(first_name: "Ivy", last_name: "Reyes")
  rosa = Person.find_by!(first_name: "Rosa", last_name: "Vale")
  cards = { ivy => "10000101", rosa => "10000102" }.to_h do |person, value|
    [ person, Token.find_or_create_by!(value: value) { |token| token.tokenable = person } ]
  end
  s.report "Family agreement lists at the time kiosk while not done: scan card #{cards[ivy].value} (Ivy; lists it), #{cards[rosa].value} (Rosa; done)"
  s.expect("the agreement is marked for the kiosk") { agreement.reload.show_on_kiosk? }
  s.expect("Ivy's card lists the agreement") { Checklists::KioskLines.for(ivy) == [ "Family agreement" ] }
  s.expect("Rosa's card lists nothing") { Checklists::KioskLines.for(rosa).empty? }
end
