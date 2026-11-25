# The email log's columns for the person merge registry. Guarded, so this
# branch runs without feature/person-merge. to_prepare runs after every
# initializer, so the registry is loaded by then whatever the file order.
Rails.application.config.to_prepare do
  next unless defined?(GatherPack::PersonMerge)

  merge = GatherPack::PersonMerge

  merge.register :sent_emails, :person_id, label: "Emails sent to them"
  # What an email was about can be a person or a login; both are covered.
  { person: "", user: " (login)" }.each do |owner, suffix|
    merge.register :sent_emails, :about_id, type_column: :about_type, owner: owner,
      label: "Emails about them#{suffix}"
  end
end
