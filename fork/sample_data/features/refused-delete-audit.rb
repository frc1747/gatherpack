# Nothing to add: try deleting a record others still use, then check the audit log.
Hbr::SampleData.feature "feature/refused-delete-audit" do |s|
  s.note "no data needed (a refused delete leaves no destroy entry in the audit log)"
end
