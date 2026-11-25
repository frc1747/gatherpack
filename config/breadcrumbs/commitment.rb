crumb :commitments do
  link "Commitments", commitments_path
end

crumb :commitment do |commitment|
  link commitment.new_record? ? "New commitment" : commitment.identifier_name, commitment
  parent :commitments
end

crumb :person_commitments do |person|
  link "#{person.display_name}'s commitments", person_commitments_path(person)
  parent :commitments
end
