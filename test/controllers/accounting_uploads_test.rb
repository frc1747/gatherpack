require "test_helper"
require_relative "../support/accounting_world"

class AccountingUploadsTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers
  include ActiveJob::TestHelper
  include AccountingWorld

  setup do
    host! "localhost"
    @source = create_file_source
    @admin = create_accounting_user("Admin", admin: true)
    @builder = create_accounting_user("Builder", architect: true)
    @member = create_accounting_user("Member")
  end

  test "an upload shows a preview of what it adds, and Apply copies the records" do
    sign_in @admin

    with_accounting { post accounting_connection_uploads_path(@source), params: { file: csv("dues.csv") } }
    upload = @source.accounting_uploads.sole
    assert_redirected_to accounting_connection_upload_path(@source, upload)
    assert_equal @admin.person, upload.created_by

    with_accounting { get accounting_connection_upload_path(@source, upload) }
    assert_response :success
    assert_match "Applying adds 12, changes 0 and removes 0", response.body
    assert_select "td", text: "Charge 1042 · Dues"
    assert_select "button:not([disabled])", text: "Apply"

    with_accounting do
      post apply_accounting_connection_upload_path(@source, upload)
      assert_redirected_to accounting_connection_records_path(@source)
      perform_enqueued_jobs only: Accounting::ApplyUploadJob
    end

    assert_equal "applied", upload.reload.status
    assert_equal @admin.person, upload.applied_by
    assert_equal 2, @source.accounting_records.current.where(role: "charge").count
  end

  test "a second upload previews the changes and removals" do
    sign_in @admin
    apply_file(file_fixture("accounting/dues.csv").read)

    changed = file_fixture("accounting/dues.csv").read.sub("450.00", "475.00").lines.reject { |line| line.start_with?("Ward Family") }.join
    with_accounting { post accounting_connection_uploads_path(@source), params: { file: upload_file(changed) } }
    with_accounting { follow_redirect! }

    assert_match "Applying adds 0, changes 1 and removes 3", response.body
  end

  test "row errors are listed and block Apply" do
    sign_in @admin

    with_accounting { post accounting_connection_uploads_path(@source), params: { file: csv("problems.csv") } }
    upload = @source.accounting_uploads.sole
    with_accounting { get accounting_connection_upload_path(@source, upload) }

    assert_select "td", text: "A charge needs a number."
    assert_select "button[disabled]", text: "Apply"

    with_accounting { post apply_accounting_connection_upload_path(@source, upload) }
    assert_redirected_to accounting_connection_upload_path(@source, upload)
    assert_equal "previewed", upload.reload.status
    assert_no_enqueued_jobs only: Accounting::ApplyUploadJob
  end

  test "an upload needs a file" do
    sign_in @admin

    with_accounting { post accounting_connection_uploads_path(@source) }

    assert_response :unprocessable_entity
    assert_match "Choose a CSV file to upload.", response.body
    assert_empty @source.accounting_uploads
  end

  test "the template downloads, and the records page offers Upload" do
    sign_in @admin

    with_accounting { get template_accounting_connection_uploads_path(@source) }
    assert_response :success
    assert_equal "text/csv", response.media_type
    assert_equal Accounting::Files::Template.csv, response.body

    with_accounting { get accounting_connection_records_path(@source) }
    assert_select "a", text: "Upload"
    assert_select "button", text: "Sync now", count: 0
  end

  test "only admins upload" do
    [ @builder, @member ].each do |user|
      sign_in user
      with_accounting { get new_accounting_connection_upload_path(@source) }
      assert_redirected_to root_path
      with_accounting { post accounting_connection_uploads_path(@source), params: { file: csv("dues.csv") } }
      sign_out user
    end

    assert_empty @source.accounting_uploads
  end

  test "a source without uploads has no upload page" do
    sign_in @admin
    ledgers = create_ledger_source

    with_accounting { get new_accounting_connection_upload_path(ledgers) }

    assert_redirected_to root_path
  end

  test "uploading is refused while accounting is off" do
    sign_in @admin

    with_accounting(false) { get new_accounting_connection_upload_path(@source) }

    assert_redirected_to root_path
    assert_equal "Accounting is turned off", flash[:notice]
  end

  test "the file source's gateway page explains it" do
    sign_in @builder

    with_accounting { get gateway_path(@source) }

    assert_response :success
    assert_match "Upload a CSV exported from your accounting program", response.body
    assert_select "a", text: "Upload"
  end

  test "the ledger source's gateway page explains it" do
    sign_in @builder
    ledgers = create_ledger_source

    with_accounting { get gateway_path(ledgers) }

    assert_response :success
    assert_match "Payments count against the oldest charges first.", response.body
    assert_match "Which teams' ledgers: every team.", response.body.squish
  end

  private
    def csv(name)
      fixture_file_upload("accounting/#{name}", "text/csv")
    end

    def upload_file(content)
      file = Tempfile.new([ "upload", ".csv" ])
      file.write(content)
      file.rewind
      Rack::Test::UploadedFile.new(file.path, "text/csv", original_filename: "dues.csv")
    end

    def apply_file(content)
      upload = @source.accounting_uploads.new(content: content, created_by: @admin.person).read_content
      upload.update!(status: "applying")
      with_accounting { Accounting::ApplyUploadJob.perform_now(@source, upload) }
    end
end
