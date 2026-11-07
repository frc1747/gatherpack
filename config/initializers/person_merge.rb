require Rails.root.join("lib/gatherpack/person_merge").to_s

# Merging two people into one. Every column that points at a person or a
# login is registered here (or exempted), so a merge leaves nothing behind.
# Features that add such a column register it from their own initializer.
Rails.application.config.to_prepare do
  GatherPack::Features.register(
    GatherPack::Feature.new(
      key: :person_merge,
      label: "Merge people",
      description: "Let admins merge two records of the same person into one",
      default_enabled: false,
      setup_section: "People",
      setup_items: [
        GatherPack::Feature::SetupItem.new(label: "Merge People", path: :new_person_merge_path, policy_check: ->(view) { view.admin? })
      ]
    )
  )

  merge = GatherPack::PersonMerge
  merge.reset!

  merge.register :memberships, :person_id, unique_by: :team_id, model: Membership, label: "Team memberships",
    on_conflict: ->(removed, kept) {
      if ActiveModel::Type::Boolean.new.cast(removed["manager"])
        Membership.where(id: kept["id"]).update_all(manager: true)
      end
    }
  merge.register :membership_applications, :person_id, unique_by: :team_id, where: { status: 0 },
    model: MembershipApplication, label: "Team applications"
  merge.register :relationships, :parent_id, unique_by: %i[relationship_type_id child_id], other_side: :child_id,
    model: Relationship, label: "Relationships"
  merge.register :relationships, :child_id, unique_by: %i[relationship_type_id parent_id], other_side: :parent_id,
    model: Relationship, label: "Relationships"
  merge.register :badge_assignments, :person_id, unique_by: :badge_id, model: BadgeAssignment, label: "Badges"
  merge.register :checkins, :person_id, unique_by: :event_id, model: Checkin, label: "Check-ins"
  merge.register :time_clock_punches, :person_id, label: "Time clock punches"
  merge.register :questions, :person_id, label: "Questions"
  merge.register :replies, :person_id, label: "Replies"
  merge.register :reply_votes, :person_id, unique_by: :question_id, model: ReplyVote, label: "Reply votes"
  merge.register :lego_lottery_drawing_tickets, :person_id, label: "Drawing tickets"

  # Polymorphic columns can point at a person or a login; both are covered.
  { person: "", user: " (login)" }.each do |owner, suffix|
    merge.register :tokens, :tokenable_id, type_column: :tokenable_type, owner: owner, label: "Cards#{suffix}"
    merge.register :calendar_notes, :noteable_id, type_column: :noteable_type, owner: owner, label: "Calendar notes#{suffix}"
    merge.register :ledger_ownerships, :owner_id, type_column: :owner_type, unique_by: :ledger_id, model: LedgerOwnership,
      owner: owner, label: "Ledgers#{suffix}"
    merge.register :mailbox_assignments, :target_id, type_column: :target_type, unique_by: :mailbox_id, model: MailboxAssignment,
      owner: owner, label: "Mailboxes#{suffix}"
    merge.register :ledger_entries, :created_by_id, type_column: :created_by_type, owner: owner, label: "Ledger entries created#{suffix}"
    merge.register :transactions, :created_by_id, type_column: :created_by_type, owner: owner, label: "Transactions created#{suffix}"
    merge.register :account_relationships, :holder_id, type_column: :holder_type, unique_by: :account_id,
      owner: owner, label: "Accounts#{suffix}"
    merge.register :active_storage_attachments, :record_id, type_column: :record_type, unique_by: :name,
      model: ActiveStorage::Attachment, owner: owner, label: "Files#{suffix}"
    merge.register :action_text_rich_texts, :record_id, type_column: :record_type, unique_by: :name,
      owner: owner, label: "Rich text#{suffix}"
  end

  # A removed login's app sign-ins are revoked rather than moved.
  merge.register :oauth_access_grants, :resource_owner_id, action: :delete, owner: :user, label: "App sign-in grants"
  merge.register :oauth_access_tokens, :resource_owner_id, action: :delete, owner: :user, label: "App sign-in tokens"
  merge.exempt :people, :user_id, owner: :user, reason: "The login itself; the merge chooses which one stays"
end
