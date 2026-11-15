require "test_helper"

class LedgerEntryReceiptsControllerTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers

  setup do
    host! "localhost"
    ledger = Ledger.create!(name: "Den A dues", team: teams(:one))
    @entry = LedgerEntry.create!(ledger: ledger, amount_cents: -1200, remark: "Pizza", created_by: users(:one))
    @entry.receipts.attach(io: StringIO.new("%PDF-1.4 receipt with card digits"), filename: "receipt.pdf")
    @receipt = @entry.receipts.first
  end

  test "a member who can see the ledger downloads the receipt" do
    sign_in users(:one)

    get ledger_ledger_entry_receipt_path(@entry.ledger, @entry, @receipt)
    assert_response :redirect
    follow_redirect!

    assert_response :success
    assert_includes response.body, "card digits"
  end

  test "a member who can't see the ledger is refused" do
    sign_in users(:two)

    get ledger_ledger_entry_receipt_path(@entry.ledger, @entry, @receipt)

    assert_response :not_found
  end

  test "an anonymous visitor is sent to sign in" do
    get ledger_ledger_entry_receipt_path(@entry.ledger, @entry, @receipt)

    assert_redirected_to new_user_session_path
  end

  test "a receipt can't be fetched through another entry" do
    other = LedgerEntry.create!(ledger: @entry.ledger, amount_cents: 5, created_by: users(:one))
    sign_in users(:one)

    get ledger_ledger_entry_receipt_path(@entry.ledger, other, @receipt)

    assert_response :not_found
  end

  test "the ledger shows the receipt through the app" do
    sign_in users(:one)

    get ledger_path(@entry.ledger)

    assert_response :success
    assert_includes response.body, ledger_ledger_entry_receipt_path(@entry.ledger, @entry, @receipt)
    assert_not_includes response.body, "/rails/active_storage/blobs/"
  end

  test "the budget shows the receipt through the app" do
    tag = LedgerTag.create!(name: "Food")
    @entry.ledger_tags << tag
    period = BudgetPeriod.create!(name: "This year", team: teams(:one), starts_at: 1.month.ago, ends_at: 1.month.from_now)
    budget = Budget.create!(budget_period: period, amount_cents: 10_000, ledger_tags: [ tag ])
    sign_in users(:one)

    get budget_path(budget)

    assert_response :success
    assert_includes response.body, ledger_ledger_entry_receipt_path(@entry.ledger, @entry, @receipt)
    assert_not_includes response.body, "/rails/active_storage/blobs/"
  end

  test "the edit form's link to a kept receipt expires" do
    sign_in admin
    get edit_ledger_ledger_entry_path(@entry.ledger, @entry)
    assert_response :success
    signed_id = kept_receipt_signed_id or flunk "no kept receipt on the form"
    sign_out admin
    link = "/rails/active_storage/blobs/redirect/#{signed_id}/receipt.pdf"

    get link
    assert_response :redirect, "the form's link opens while the form is fresh"

    travel 2.hours do
      get link
      assert_response :not_found, "the edit form's receipt link (#{link.first(48)}...) still opens 2 hours later with no session"
    end
  end

  test "a form kept open past its receipt links' expiry is shown again, not an error" do
    sign_in admin
    get edit_ledger_ledger_entry_path(@entry.ledger, @entry)
    signed_id = kept_receipt_signed_id

    # Past the link's expiry, but not so long that the session itself ends.
    travel ActiveStorage.urls_expire_in + 1.minute do
      patch ledger_ledger_entry_path(@entry.ledger, @entry), params: { ledger_entry: { remark: "Pizza and drinks", receipts: [ signed_id ] } }
    end

    assert_response :unprocessable_entity
    assert_includes response.body, "Reload the page"
    assert_equal "Pizza", @entry.reload.remark
    assert_equal [ @receipt.id ], @entry.receipts.map(&:id)
  end

  private

  # The form posts kept receipts back by signed id (the empty one comes with
  # the file field).
  def kept_receipt_signed_id
    css_select("input[type=hidden][name='ledger_entry[receipts][]']").map { |input| input["value"] }.compact_blank.first
  end

  def admin
    @admin ||= User.create!(email: "receipts-admin@example.com", password: "Password1!", admin: true).tap do |user|
      Person.create!(user: user, first_name: "Ada", last_name: "Admin")
    end
  end
end
