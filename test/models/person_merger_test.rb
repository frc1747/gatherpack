require "test_helper"

class PersonMergerTest < ActiveSupport::TestCase
  setup do
    @admin = User.create!(email: "merge-admin@example.com", password: "Password1!", admin: true)
    Person.create!(user: @admin, first_name: "Ada", last_name: "Admin")
    @keep = Person.create!(first_name: "Dana", last_name: "Rivers")
    @drop = Person.create!(first_name: "Dana", last_name: "Rivers", phone_number: "555-0199")
  end

  # One row per registered person column, owned by drop. Each returns
  # [table, id] so the test can check the row now points at keep.
  ROWS = {
    "memberships" => -> { [ "memberships", Membership.create!(person: @drop, team: teams(:one)).id ] },
    "membership_applications" => -> { [ "membership_applications", saved(MembershipApplication.new(person: @drop, team: teams(:one))).id ] },
    "relationships.parent_id" => -> { [ "relationships", saved(Relationship.new(parent: @drop, child: people(:one), relationship_type: relationship_types(:one))).id ] },
    "relationships.child_id" => -> { [ "relationships", saved(Relationship.new(parent: people(:one), child: @drop, relationship_type: relationship_types(:one))).id ] },
    "badge_assignments" => -> { [ "badge_assignments", saved(BadgeAssignment.new(person: @drop, badge: badges(:one))).id ] },
    "checkins" => -> { [ "checkins", saved(Checkin.new(person: @drop, event: events(:one))).id ] },
    "time_clock_punches" => -> { [ "time_clock_punches", saved(TimeClockPunch.new(person: @drop, start_time: 1.hour.ago)).id ] },
    "questions" => -> { [ "questions", Question.create!(person: @drop, team: teams(:one), title: "Room?", content: "Which room?").id ] },
    "replies" => -> { [ "replies", Reply.create!(person: @drop, question: questions(:one), content: "Room 4").id ] },
    "reply_votes" => -> { [ "reply_votes", ReplyVote.create!(person: @drop, question: questions(:two), reply: replies(:one).tap { |r| r.update_columns(question_id: questions(:two).id) }).id ] },
    "lego_lottery_drawing_tickets" => -> { [ "lego_lottery_drawing_tickets", insert_row(:lego_lottery_drawing_tickets, lego_lottery_drawing_id: insert_row(:lego_lottery_drawings, name: "Draw"), person_id: @drop.id) ] },
    "tokens" => -> { [ "tokens", Token.create!(tokenable: @drop, value: "merge-card").id ] },
    "calendar_notes" => -> { [ "calendar_notes", CalendarNote.create!(noteable: @drop, name: "Away", start_time: Time.current).id ] },
    "ledger_ownerships" => -> { [ "ledger_ownerships", LedgerOwnership.create!(owner: @drop, ledger: ledgers(:one)).id ] },
    "mailbox_assignments" => -> { [ "mailbox_assignments", MailboxAssignment.create!(target: @drop, mailbox: mailboxes(:one)).id ] },
    "ledger_entries" => -> { [ "ledger_entries", insert_row(:ledger_entries, ledger_id: ledgers(:one).id, created_by_id: @drop.id, created_by_type: "Person", amount_cents: 100) ] },
    "transactions" => -> { [ "transactions", insert_row(:transactions, account_id: account_id, created_by_id: @drop.id, created_by_type: "Person") ] },
    "account_relationships" => -> { [ "account_relationships", insert_row(:account_relationships, account_id: account_id, holder_id: @drop.id, holder_type: "Person") ] },
    "active_storage_attachments" => -> { @drop.avatar.attach(io: StringIO.new("img"), filename: "a.png"); [ "active_storage_attachments", @drop.avatar.attachment.id ] },
    "action_text_rich_texts" => -> { [ "action_text_rich_texts", insert_row(:action_text_rich_texts, name: "notes", body: "Hi", record_type: "Person", record_id: @drop.id) ] }
  }.freeze

  ROWS.each do |name, build|
    test "moves #{name} to the kept person" do
      table, id = instance_exec(&build)
      entry = GatherPack::PersonMerge.entries(:person).find { |e| e.table == table && (name.exclude?(".") || name.end_with?(e.column)) }

      assert merge.merge(actor: @admin), merge.errors.full_messages.to_sentence
      assert_equal @keep.id, column_value(table, entry.column, id)
    end
  end

  test "every registered person column has a move test" do
    tested = ROWS.keys.map { |name| name.include?(".") ? name : "#{name}.#{GatherPack::PersonMerge.entries(:person).find { |e| e.table == name }.column}" }
    registered = GatherPack::PersonMerge.entries(:person).map { |e| "#{e.table}.#{e.column}" }

    assert_empty registered - tested
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

  test "removes a duplicate badge" do
    saved(BadgeAssignment.new(person: @keep, badge: badges(:one)))
    saved(BadgeAssignment.new(person: @drop, badge: badges(:one)))

    assert merge.merge(actor: @admin)
    assert_equal 1, BadgeAssignment.where(person: @keep, badge: badges(:one)).count
  end

  test "removes a check-in at an event the kept person already checked in to" do
    saved(Checkin.new(person: @keep, event: events(:one)))
    saved(Checkin.new(person: @drop, event: events(:one)))

    assert merge.merge(actor: @admin)
    assert_equal 1, Checkin.where(person: @keep, event: events(:one)).count
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
    application = OauthApplication.create!(name: "App", redirect_uri: "https://example.com/cb")
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

  def column_value(table, column, id)
    connection = ActiveRecord::Base.connection
    connection.select_value(ActiveRecord::Base.sanitize_sql_array([
      "SELECT #{connection.quote_column_name(column)} FROM #{connection.quote_table_name(table)} WHERE id = ?", id
    ]))
  end
end
