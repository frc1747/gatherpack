require "test_helper"

class LedgerEntriesControllerTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers

  setup do
    host! "localhost"

    @robotics = Team.create!(name: "Robotics", team_type: team_types(:one))
    @drama = Team.create!(name: "Drama", team_type: team_types(:one))

    @admin_user = User.create!(email: "admin@example.com", password: "Password1!", admin: true)
    Person.create!(user: @admin_user, first_name: "Ada", last_name: "Admin")

    @manager_user = User.create!(email: "manager@example.com", password: "Password1!")
    @manager = Person.create!(user: @manager_user, first_name: "Mary", last_name: "Manager")
    Membership.create!(person: @manager, team: @robotics, manager: true)

    @robotics_ledger = Ledger.create!(name: "Robotics fund", team: @robotics)
    @robotics_reserve = Ledger.create!(name: "Robotics reserve", team: @robotics)
    @drama_ledger = Ledger.create!(name: "Drama fund", team: @drama)
    LedgerEntry.create!(ledger: @drama_ledger, amount_cents: 100_000, remark: "Seed", created_by: @admin_user)
  end

  # --- transfers between teams --------------------------------------------

  test "a manager can't edit their half of a transfer when the other half is another team's" do
    outgoing, incoming = transfer(@drama_ledger, @robotics_ledger, 10)
    sign_in @manager_user

    patch ledger_ledger_entry_path(@robotics_ledger, incoming), params: { ledger_entry: { amount: "-900" } }

    assert_equal 99_000, @drama_ledger.reload.balance_cents, "manager of Robotics changed the Drama ledger's balance"
    assert_equal(-1_000, outgoing.reload.amount_cents)
    assert_equal 1_000, incoming.reload.amount_cents
    assert_redirected_to root_path
  end

  test "a manager can't open the edit form for their half of a transfer with another team" do
    _, incoming = transfer(@drama_ledger, @robotics_ledger, 10)
    sign_in @manager_user

    get edit_ledger_ledger_entry_path(@robotics_ledger, incoming)

    assert_redirected_to root_path
  end

  test "a manager can't delete their half of a transfer when the other half is another team's" do
    outgoing, incoming = transfer(@robotics_ledger, @drama_ledger, 300)
    sign_in @manager_user

    delete ledger_ledger_entry_path(@robotics_ledger, outgoing)

    assert_equal 130_000, @drama_ledger.reload.balance_cents, "manager of Robotics deleted Drama's incoming half of a transfer"
    assert LedgerEntry.exists?(incoming.id)
    assert LedgerEntry.exists?(outgoing.id)
    assert_redirected_to root_path
  end

  test "an admin editing the amount of one half of a transfer mirrors it on the other half" do
    outgoing, incoming = transfer(@drama_ledger, @robotics_ledger, 10)
    sign_in @admin_user

    patch ledger_ledger_entry_path(@robotics_ledger, incoming), params: { ledger_entry: { amount: "25", remark: "Corrected", approved: "1" } }

    assert_redirected_to ledger_ledger_entry_path(@robotics_ledger, incoming)
    assert_equal 2_500, incoming.reload.amount_cents
    assert_equal(-2_500, outgoing.reload.amount_cents)
    assert_equal 97_500, @drama_ledger.reload.balance_cents
    assert_equal 2_500, @robotics_ledger.reload.balance_cents
  end

  test "editing one half of a transfer doesn't copy anything but the amount to the other half" do
    outgoing, incoming = transfer(@drama_ledger, @robotics_ledger, 10)
    tag = LedgerTag.create!(name: "Travel")
    sign_in @admin_user

    patch ledger_ledger_entry_path(@robotics_ledger, incoming), params: { ledger_entry: { remark: "Corrected", approved: "1", ledger_tag_ids: [ tag.id ] } }

    outgoing.reload
    assert_equal "Transfer to Robotics fund", outgoing.remark
    assert_not outgoing.approved
    assert_empty outgoing.ledger_tags
    assert_equal(-1_000, outgoing.amount_cents)
  end

  test "an admin editing the outgoing half of a transfer mirrors it on the incoming half" do
    outgoing, incoming = transfer(@drama_ledger, @robotics_ledger, 10)
    sign_in @admin_user

    patch ledger_ledger_entry_path(@drama_ledger, outgoing), params: { ledger_entry: { amount: "40" } }

    assert_equal(-4_000, outgoing.reload.amount_cents)
    assert_equal 4_000, incoming.reload.amount_cents
  end

  test "an admin deleting one half of a transfer deletes both" do
    outgoing, incoming = transfer(@robotics_ledger, @drama_ledger, 300)
    sign_in @admin_user

    delete ledger_ledger_entry_path(@robotics_ledger, outgoing)

    assert_redirected_to ledger_path(@robotics_ledger)
    assert_not LedgerEntry.exists?(outgoing.id)
    assert_not LedgerEntry.exists?(incoming.id)
    assert_equal 100_000, @drama_ledger.reload.balance_cents
  end

  # --- transfers within the manager's own ledgers -------------------------

  test "a manager of both sides of a transfer can edit it" do
    outgoing, incoming = transfer(@robotics_ledger, @robotics_reserve, 10)
    sign_in @manager_user

    patch ledger_ledger_entry_path(@robotics_reserve, incoming), params: { ledger_entry: { amount: "15" } }

    assert_redirected_to ledger_ledger_entry_path(@robotics_reserve, incoming)
    assert_equal 1_500, incoming.reload.amount_cents
    assert_equal(-1_500, outgoing.reload.amount_cents)
  end

  test "a manager of both sides of a transfer can delete it" do
    outgoing, incoming = transfer(@robotics_ledger, @robotics_reserve, 10)
    sign_in @manager_user

    delete ledger_ledger_entry_path(@robotics_reserve, incoming)

    assert_redirected_to ledger_path(@robotics_reserve)
    assert_not LedgerEntry.exists?(outgoing.id)
    assert_not LedgerEntry.exists?(incoming.id)
  end

  test "a manager can edit an ordinary entry in their team's ledger" do
    entry = LedgerEntry.create!(ledger: @robotics_ledger, amount_cents: 500, remark: "Bake sale", created_by: @admin_user)
    sign_in @manager_user

    patch ledger_ledger_entry_path(@robotics_ledger, entry), params: { ledger_entry: { amount: "7", remark: "Bake sale (recounted)" } }

    assert_redirected_to ledger_ledger_entry_path(@robotics_ledger, entry)
    assert_equal 700, entry.reload.amount_cents
    assert_equal 700, @robotics_ledger.reload.balance_cents
  end

  private

  def transfer(from_ledger, to_ledger, amount)
    t = LedgerTransfer.new(from_ledger_id: from_ledger.id, to_ledger_id: to_ledger.id, amount: amount)
    t.creator = @admin_user
    t.create
    [ from_ledger.ledger_entries.find_by!(remark: "Transfer to #{to_ledger.name}"),
      to_ledger.ledger_entries.find_by!(remark: "Transfer from #{from_ledger.name}") ]
  end
end
