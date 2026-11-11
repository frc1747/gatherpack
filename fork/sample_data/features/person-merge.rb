# Two records of the same person, ready to merge from Setup > Merge People
# (admin@). Nora Lindqvist is the record to keep; Nora Lindquist is the
# misspelled duplicate. Both are on Facilities Crew (that membership shows as
# removed in the preview), only the duplicate is on Youth Program (it moves),
# and the duplicate has a phone number the kept record lacks (it is filled in).
Hbr::SampleData.people "Nora Lindqvist", "Nora Lindquist"

Hbr::SampleData.feature "feature/person-merge" do |s|
  s.enable_feature :person_merge
  keep = s.person!("Nora", "Lindqvist")
  duplicate = s.person!("Nora", "Lindquist", phone_number: "555-0150")
  s.member!(keep, s.team(:facilities))
  s.member!(duplicate, s.team(:facilities))
  s.member!(duplicate, s.team(:youth))
  s.report "2 records of Nora to merge (Setup > Merge People)"
  s.expect("the preview moves one membership and removes one") do
    change = PersonMerger.new(keep_nid: keep.neat_id, drop_nid: duplicate.neat_id).changes.find { |c| c.entry.table == "memberships" }
    change.moving.size == 1 && change.removing.size == 1
  end
end
