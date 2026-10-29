require "test_helper"

class DirectUploadsTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers

  BODY = "%PDF-1.4 a receipt".freeze

  setup { host! "localhost" }

  test "an anonymous visitor cannot create a direct-upload blob" do
    assert_no_difference -> { ActiveStorage::Blob.count }, "an anonymous visitor created a direct-upload blob" do
      post rails_direct_uploads_path, params: { blob: blob_params }, as: :json
    end

    assert_response :unauthorized
    assert_nil response.parsed_body["direct_upload"]
  end

  test "a signed-in member can create a direct-upload blob within the limits" do
    sign_in users(:one)

    assert_difference -> { ActiveStorage::Blob.count }, 1 do
      post rails_direct_uploads_path, params: { blob: blob_params }, as: :json
    end

    assert_response :success
    put response.parsed_body.dig("direct_upload", "url"), params: BODY, headers: response.parsed_body.dig("direct_upload", "headers")
    assert_response :no_content
    assert_equal BODY, ActiveStorage::Blob.last.download
  end

  test "a direct upload over the size limit is refused" do
    sign_in users(:one)

    assert_no_difference -> { ActiveStorage::Blob.count }, "a blob over the size limit was created" do
      post rails_direct_uploads_path, params: { blob: blob_params(byte_size: 10.megabytes + 1) }, as: :json
    end

    assert_response :unprocessable_entity
  end

  test "a direct upload of a type no attachment accepts is refused" do
    sign_in users(:one)

    assert_no_difference -> { ActiveStorage::Blob.count }, "a text/html blob was created" do
      post rails_direct_uploads_path, params: { blob: blob_params(filename: "page.html", content_type: "text/html") }, as: :json
    end

    assert_response :unprocessable_entity
  end

  test "the daily cleanup purges blobs left unattached for over a day" do
    stale, attached = travel_to(2.days.ago) do
      [ "stale.pdf", "kept.pdf" ].map { |name| ActiveStorage::Blob.create_and_upload!(io: StringIO.new(BODY), filename: name) }
    end
    fresh = ActiveStorage::Blob.create_and_upload!(io: StringIO.new(BODY), filename: "fresh.pdf")
    ledger_entries(:one).receipts.attach(attached)
    command = YAML.load_file(Rails.root.join("config/recurring.yml")).dig("purge_unattached_blobs", "command")
    assert command, "no recurring task purges unattached blobs"

    perform_enqueued_jobs { SolidQueue::RecurringJob.perform_now(command) }

    assert_not ActiveStorage::Blob.exists?(stale.id)
    assert ActiveStorage::Blob.exists?(fresh.id)
    assert ActiveStorage::Blob.exists?(attached.id)
  end

  private

  def blob_params(**overrides)
    { filename: "receipt.pdf", byte_size: BODY.bytesize, checksum: Digest::MD5.base64digest(BODY), content_type: "application/pdf" }.merge(overrides)
  end
end
