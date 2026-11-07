require "test_helper"

class PersonMergerTest < ActiveSupport::TestCase
  setup do
    @admin = User.create!(email: "merge-admin@example.com", password: "Password1!", admin: true)
    Person.create!(user: @admin, first_name: "Ada", last_name: "Admin")
    @keep = Person.create!(first_name: "Dana", last_name: "Rivers")
    @drop = Person.create!(first_name: "Dana", last_name: "Rivers", phone_number: "555-0199")
  end

  # Builders for one row pointing at `o`, returning its id. Polymorphic ones
  # are used for both owners: `o` is the person merged away, or the login
  # the merge deletes.
  PERSON_ROWS = {
    "memberships.person_id" => ->(o) { Membership.create!(person: o, team: teams(:one)).id },
    "membership_applications.person_id" => ->(o) { saved(MembershipApplication.new(person: o, team: teams(:one))).id },
    "relationships.parent_id" => ->(o) { saved(Relationship.new(parent: o, child: people(:one), relationship_type: relationship_types(:one))).id },
    "relationships.child_id" => ->(o) { saved(Relationship.new(parent: people(:one), child: o, relationship_type: relationship_types(:one))).id },
    "badge_assignments.person_id" => ->(o) { saved(BadgeAssignment.new(person: o, badge: badges(:one))).id },
    "checkins.person_id" => ->(o) { saved(Checkin.new(person: o, event: events(:one))).id },
    "time_clock_punches.person_id" => ->(o) { saved(TimeClockPunch.new(person: o, start_time: 1.hour.ago)).id },
    "questions.person_id" => ->(o) { Question.create!(person: o, team: teams(:one), title: "Room?", content: "Which room?").id },
    "replies.person_id" => ->(o) { Reply.create!(person: o, question: questions(:one), content: "Room 4").id },
    "reply_votes.person_id" => ->(o) { ReplyVote.create!(person: o, question: questions(:one), reply: replies(:one)).id },
    "lego_lottery_drawing_tickets.person_id" => ->(o) { insert_row(:lego_lottery_drawing_tickets, lego_lottery_drawing_id: insert_row(:lego_lottery_drawings, name: "Draw"), person_id: o.id) }
  }.freeze

  POLYMORPHIC_ROWS = {
    "tokens.tokenable_id" => ->(o) { Token.create!(tokenable: o, value: "merge-card-#{o.id}").id },
    "calendar_notes.noteable_id" => ->(o) { CalendarNote.create!(noteable: o, name: "Away", start_time: Time.current).id },
    "ledger_ownerships.owner_id" => ->(o) { LedgerOwnership.create!(owner: o, ledger: ledgers(:one)).id },
    "mailbox_assignments.target_id" => ->(o) { MailboxAssignment.create!(target: o, mailbox: mailboxes(:one)).id },
    "ledger_entries.created_by_id" => ->(o) { insert_row(:ledger_entries, ledger_id: ledgers(:one).id, created_by_id: o.id, created_by_type: o.class.name, amount_cents: 100) },
    "transactions.created_by_id" => ->(o) { insert_row(:transactions, account_id: account_id, created_by_id: o.id, created_by_type: o.class.name) },
    "account_relationships.holder_id" => ->(o) { insert_row(:account_relationships, account_id: account_id, holder_id: o.id, holder_type: o.class.name) },
    "active_storage_attachments.record_id" => ->(o) { insert_row(:active_storage_attachments, name: "avatar", record_type: o.class.name, record_id: o.id, blob_id: blob_id) },
    "action_text_rich_texts.record_id" => ->(o) { insert_row(:action_text_rich_texts, name: "notes", body: "Hi", record_type: o.class.name, record_id: o.id) }
  }.freeze

  USER_ROWS = {
    "oauth_access_grants.resource_owner_id" => ->(o) { insert_row(:oauth_access_grants, application_id: oauth_application_id, resource_owner_id: o.id, token: "g-#{o.id}", expires_in: 60, redirect_uri: "https://example.com/cb") },
    "oauth_access_tokens.resource_owner_id" => ->(o) { insert_row(:oauth_access_tokens, application_id: oauth_application_id, resource_owner_id: o.id, token: "t-#{o.id}") }
  }.freeze

  ROWS = PERSON_ROWS.transform_keys { |k| "person:#{k}" }
    .merge(POLYMORPHIC_ROWS.transform_keys { |k| "person:#{k}" })
    .merge(POLYMORPHIC_ROWS.transform_keys { |k| "user:#{k}" })
    .merge(USER_ROWS.transform_keys { |k| "user:#{k}" }).freeze

  ROWS.each do |key, build|
    test "merges #{key}" do
      entry = entry_for(key)
      from, to = owners_for(entry.owner)
      id = instance_exec(from, &build)

      assert merge(keep_login: "keep").merge(actor: @admin), "merge refused"
      if entry.action == :delete
        assert_nil column_value(entry.table, :id, id)
      else
        assert_equal to.id, column_value(entry.table, entry.column, id)
      end
    end
  end

  # Builders for a duplicate: a row for `from` that `to` already has.
  # Returns [from's row id, to's row id].
  PERSON_CONFLICTS = {
    "memberships.person_id" => ->(from, to) { [ from, to ].map { |o| Membership.create!(person: o, team: teams(:one)).id } },
    "membership_applications.person_id" => ->(from, to) { [ from, to ].map { |o| saved(MembershipApplication.new(person: o, team: teams(:one))).id } },
    "relationships.parent_id" => ->(from, to) { [ from, to ].map { |o| saved(Relationship.new(parent: o, child: people(:one), relationship_type: relationship_types(:one))).id } },
    "relationships.child_id" => ->(from, to) { [ from, to ].map { |o| saved(Relationship.new(parent: people(:one), child: o, relationship_type: relationship_types(:one))).id } },
    "badge_assignments.person_id" => ->(from, to) { [ from, to ].map { |o| saved(BadgeAssignment.new(person: o, badge: badges(:one))).id } },
    "checkins.person_id" => ->(from, to) { [ from, to ].map { |o| saved(Checkin.new(person: o, event: events(:one))).id } },
    "reply_votes.person_id" => ->(from, to) { [ from, to ].map { |o| ReplyVote.create!(person: o, question: questions(:one), reply: replies(:one)).id } }
  }.freeze

  POLYMORPHIC_CONFLICTS = %w[
    ledger_ownerships.owner_id mailbox_assignments.target_id account_relationships.holder_id
    active_storage_attachments.record_id action_text_rich_texts.record_id
  ].to_h { |k| [ k, ->(from, to) { [ from, to ].map { |o| instance_exec(o, &POLYMORPHIC_ROWS.fetch(k)) } } ] }.freeze

  CONFLICTS = PERSON_CONFLICTS.transform_keys { |k| "person:#{k}" }
    .merge(POLYMORPHIC_CONFLICTS.transform_keys { |k| "person:#{k}" })
    .merge(POLYMORPHIC_CONFLICTS.transform_keys { |k| "user:#{k}" }).freeze

  CONFLICTS.each do |key, build|
    test "removes a duplicate in #{key}" do
      entry = entry_for(key)
      from, to = owners_for(entry.owner)
      from_id, to_id = instance_exec(from, to, &build)

      assert merge(keep_login: "keep").merge(actor: @admin), "merge refused"
      assert_nil column_value(entry.table, :id, from_id)
      assert_equal to.id, column_value(entry.table, entry.column, to_id)
    end
  end

  test "every registered column has a merge test" do
    registered = GatherPack::PersonMerge.entries.map { |e| "#{e.owner}:#{e.table}.#{e.column}" }

    assert_empty registered - ROWS.keys
  end

  test "every column with duplicates has a conflict test" do
    registered = GatherPack::PersonMerge.entries.select { |e| e.unique_by.any? }.map { |e| "#{e.owner}:#{e.table}.#{e.column}" }

    assert_empty registered - CONFLICTS.keys
  end

  test "deletes the merged person and records one merge entry" do
    Membership.create!(person: @drop, team: teams(:one))

    assert_difference -> { Person.count }, -1 do
      assert_difference -> { AuditLog.where(event: "merge").count }, 1 do
        assert merge.merge(actor: @admin)
      end
    end
    assert_not Person.exists?(@drop.id)

    log = AuditLog.find_by(event: "merge")
    assert_equal @keep.id, log.item_id
    assert_equal @admin.id, log.whodunnit
    changes = PaperTrail.serializer.load(log.object_changes)
    assert_includes changes.keys, "memberships.person_id moved"
    assert_includes changes["merged_person"].first, @drop.id
  end

  test "fills the kept person's blank fields only" do
    @keep.update!(shirt_size: "M")
    @drop.update!(shirt_size: "L")

    assert merge.merge(actor: @admin)
    assert_equal "555-0199", @keep.reload.phone_number
    assert_equal "M", @keep.shirt_size
  end

  test "removes a duplicate team membership and keeps manager access" do
    kept = Membership.create!(person: @keep, team: teams(:one))
    Membership.create!(person: @drop, team: teams(:one), manager: true)
    Membership.create!(person: @drop, team: teams(:two))

    assert merge.merge(actor: @admin)
    assert_equal [ teams(:one), teams(:two) ].map(&:id).sort, @keep.memberships.pluck(:team_id).sort
    assert kept.reload.manager
  end

  test "a duplicate check-in keeps the removed one's notes and answers" do
    field = checkin_fields(:one)
    other_field = CheckinField.create!(event_type: field.event_type, name: "Ride home")
    kept = saved(Checkin.new(person: @keep, event: events(:one)))
    removed = saved(Checkin.new(person: @drop, event: events(:one), notes: "arrived late"))
    CheckinFieldResponse.create!(checkin: kept, checkin_field: field, response: "")
    CheckinFieldResponse.create!(checkin: kept, checkin_field: other_field, response: "Bus")
    CheckinFieldResponse.create!(checkin: removed, checkin_field: field, response: "Yes")
    CheckinFieldResponse.create!(checkin: removed, checkin_field: other_field, response: "Car")

    assert merge.merge(actor: @admin)
    assert_not Checkin.exists?(removed.id)
    kept.reload
    assert_equal "arrived late", kept.notes
    assert_equal({ field.id => "Yes", other_field.id => "Bus" }, kept.checkin_field_responses.pluck(:checkin_field_id, :response).to_h)
  end

  test "warns about overlapping and open punches but still moves them" do
    saved(TimeClockPunch.new(person: @keep, start_time: 2.hours.ago))
    open = saved(TimeClockPunch.new(person: @drop, start_time: 1.hour.ago))
    saved(TimeClockPunch.new(person: @drop, start_time: 3.days.ago, end_time: 3.days.ago + 1.hour))

    change = merge.changes.find { |c| c.entry.table == "time_clock_punches" }
    assert_equal 2, change.moving.size
    assert_includes change.warning, "1 punch overlap"
    assert_includes change.warning, "Both are clocked in"

    assert merge.merge(actor: @admin)
    assert_equal @keep.id, open.reload.person_id
    log = PaperTrail.serializer.load(AuditLog.find_by(event: "merge").object_changes)
    assert log.key?("time_clock_punches.person_id warning")
  end

  test "no punch warning when punches don't overlap" do
    saved(TimeClockPunch.new(person: @keep, start_time: 2.days.ago, end_time: 2.days.ago + 1.hour))
    saved(TimeClockPunch.new(person: @drop, start_time: 3.days.ago, end_time: 3.days.ago + 1.hour))

    assert_nil merge.changes.find { |c| c.entry.table == "time_clock_punches" }.warning
  end

  test "removes relationships between the two people and duplicate relationships" do
    type = relationship_types(:one)
    saved(Relationship.new(parent: @drop, child: @keep, relationship_type: type))
    saved(Relationship.new(parent: @keep, child: @drop, relationship_type: relationship_types(:two)))
    saved(Relationship.new(parent: @keep, child: people(:one), relationship_type: type))
    saved(Relationship.new(parent: @drop, child: people(:one), relationship_type: type))
    other = saved(Relationship.new(parent: @drop, child: people(:two), relationship_type: type))

    preview = merge.changes.select { |c| c.entry.table == "relationships" }
    assert_equal 3, preview.sum { |c| c.removing.size }

    assert merge.merge(actor: @admin)
    rows = Relationship.where(parent: @keep).or(Relationship.where(child: @keep))
    assert_equal 2, rows.count
    assert_equal @keep.id, other.reload.parent_id
    assert rows.none? { |r| r.parent_id == r.child_id }
  end

  test "only one pending application per team survives" do
    saved(MembershipApplication.new(person: @keep, team: teams(:one)))
    saved(MembershipApplication.new(person: @drop, team: teams(:one)))
    saved(MembershipApplication.new(person: @drop, team: teams(:one), status: :denied))

    assert merge.merge(actor: @admin)
    assert_equal 1, MembershipApplication.pending.where(person: @keep).count
    assert_equal 1, MembershipApplication.denied.where(person: @keep).count
  end

  test "previews without changing anything" do
    Membership.create!(person: @drop, team: teams(:one))

    change = merge.changes.find { |c| c.entry.table == "memberships" }
    assert_equal 1, change.moving.size
    assert Person.exists?(@drop.id)
    assert_equal 0, @keep.memberships.count
  end

  test "moves the only login to the kept person" do
    login = User.create!(email: "dana@example.com", password: "Password1!")
    @drop.update!(user: login)

    assert merge.merge(actor: @admin)
    assert_equal login, @keep.reload.user
    assert User.exists?(login.id)
  end

  test "refuses when both have logins and none is chosen" do
    @keep.update!(user: User.create!(email: "dana@example.com", password: "Password1!"))
    @drop.update!(user: User.create!(email: "dana.r@example.com", password: "Password1!"))

    merger = merge
    assert_no_difference -> { Person.count } do
      assert_not merger.merge(actor: @admin)
    end
    assert merger.errors.key?(:keep_login)
  end

  test "keeps the chosen login and deletes the other one" do
    old_login = User.create!(email: "dana@example.com", password: "Password1!")
    new_login = User.create!(email: "dana.r@example.com", password: "Password1!")
    @keep.update!(user: old_login)
    @drop.update!(user: new_login)
    application = OauthApplication.create!(name: "App", redirect_uri: "https://example.com/cb", scopes: "user_read")
    grant = insert_row(:oauth_access_grants, application_id: application.id, resource_owner_id: old_login.id, token: "g", expires_in: 60, redirect_uri: "https://example.com/cb")
    entry = insert_row(:ledger_entries, ledger_id: ledgers(:one).id, created_by_id: old_login.id, created_by_type: "User", amount_cents: 100)

    assert merge(keep_login: "drop").merge(actor: @admin)
    assert_equal new_login, @keep.reload.user
    assert_not User.exists?(old_login.id)
    assert_nil column_value(:oauth_access_grants, :id, grant)
    assert_equal new_login.id, column_value(:ledger_entries, :created_by_id, entry)
  end

  test "refuses to delete an admin login" do
    @keep.update!(user: User.create!(email: "dana@example.com", password: "Password1!", admin: true))
    @drop.update!(user: User.create!(email: "dana.r@example.com", password: "Password1!"))

    merger = merge(keep_login: "drop")
    assert_not merger.merge(actor: @admin)
    assert_includes merger.errors[:keep_login].first, "admin access"
  end

  test "references? says whether anything else points at a person" do
    loner = Person.create!(first_name: "Lee", last_name: "Park")
    assert_not GatherPack::PersonMerge.references?(loner)

    Membership.create!(person: loner, team: teams(:one))
    rows = GatherPack::PersonMerge.rows_for(loner)
    assert_equal({ "memberships" => 1 }, rows.transform_keys(&:table))
    assert GatherPack::PersonMerge.references?(loner)
    assert_not GatherPack::PersonMerge.references?(loner, except: :memberships)
  end

  test "references? counts rows pointing at the person's login" do
    loner = Person.create!(first_name: "Lee", last_name: "Park", user: User.create!(email: "lee@example.com", password: "Password1!"))
    Token.create!(tokenable: loner.user, value: "lee-card")

    assert GatherPack::PersonMerge.references?(loner)
    assert_not GatherPack::PersonMerge.references?(loner, include_login: false)
  end

  test "refuses to merge a person into themselves" do
    merger = PersonMerger.new(keep_nid: @keep.neat_id, drop_nid: @keep.neat_id)
    assert_not merger.valid?
  end

  private

  def merge(**attrs)
    PersonMerger.new(keep_nid: @keep.neat_id, drop_nid: @drop.neat_id, **attrs)
  end

  # Saves without validations, which need an acting person or other setup
  # that isn't what these tests are about.
  def saved(record)
    record.save!(validate: false)
    record
  end

  def insert_row(table, attrs)
    attrs = { created_at: Time.current, updated_at: Time.current }.merge(attrs)
    connection = ActiveRecord::Base.connection
    columns = connection.columns(table).map(&:name)
    attrs = attrs.select { |k, _| columns.include?(k.to_s) }
    sql = ActiveRecord::Base.sanitize_sql_array([
      "INSERT INTO #{connection.quote_table_name(table)} (#{attrs.keys.map { |k| connection.quote_column_name(k) }.join(', ')}) VALUES (?) RETURNING id",
      attrs.values
    ])
    connection.select_value(sql)
  end

  def account_id
    @account_id ||= insert_row(:accounts, name: "Dues")
  end

  def blob_id
    ActiveStorage::Blob.create_and_upload!(io: StringIO.new("file"), filename: "file.txt").id
  end

  def oauth_application_id
    @oauth_application_id ||= OauthApplication.create!(name: "App", redirect_uri: "https://example.com/cb", scopes: "user_read").id
  end

  def entry_for(key)
    owner, column = key.split(":")
    GatherPack::PersonMerge.entries(owner.to_sym).find { |e| "#{e.table}.#{e.column}" == column }
  end

  # [the record rows move from, the record they move to]. For logins, both
  # people get one and the merge keeps the kept person's.
  def owners_for(owner)
    return [ @drop, @keep ] if owner == :person

    @keep.update!(user: User.create!(email: "dana@example.com", password: "Password1!"))
    @drop.update!(user: User.create!(email: "dana.r@example.com", password: "Password1!"))
    [ @drop.user, @keep.user ]
  end

  def column_value(table, column, id)
    connection = ActiveRecord::Base.connection
    connection.select_value(ActiveRecord::Base.sanitize_sql_array([
      "SELECT #{connection.quote_column_name(column)} FROM #{connection.quote_table_name(table)} WHERE id = ?", id
    ]))
  end
end
