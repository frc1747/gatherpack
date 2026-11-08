require "test_helper"

class ReceiptUploadsTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers

  setup do
    host! "localhost"
    admin = User.create!(email: "receipts-admin@example.com", password: "Password1!", admin: true)
    Person.create!(user: admin, first_name: "Ada", last_name: "Admin")
    sign_in admin
    @entry = ledger_entries(:one)
  end

  test "a refused receipt shows the form again with the reason" do
    file = Rack::Test::UploadedFile.new(StringIO.new("<html></html>"), "text/html", original_filename: "receipt.html")

    patch ledger_ledger_entry_path(@entry.ledger, @entry), params: { ledger_entry: { remark: "Pizza", receipts: [ file ] } }

    assert_response :unprocessable_entity
    assert_includes response.body, "must be a PNG, JPEG, WEBP or PDF file"
    assert_not @entry.reload.receipts.attached?
  end

  test "a PDF receipt is stored" do
    file = Rack::Test::UploadedFile.new(StringIO.new("%PDF-1.4 a receipt\n"), "application/pdf", original_filename: "receipt.pdf")

    patch ledger_ledger_entry_path(@entry.ledger, @entry), params: { ledger_entry: { remark: "Pizza", receipts: [ file ] } }

    assert_response :redirect
    assert_equal [ "application/pdf" ], @entry.reload.receipts.map(&:content_type)
  end
end
