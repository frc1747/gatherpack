# Applies an uploaded file to its file source: the source's records are
# replaced with the file's, and records the file no longer has are marked
# deleted. An upload that doesn't finish goes back to its preview, as does
# one the job never applied (the feature was turned off meanwhile).
class Accounting::ApplyUploadJob < Accounting::SyncJob
  def perform(gateway, upload)
    super
  ensure
    AccountingUpload.where(id: upload.id, status: "applying").update_all(status: "previewed", updated_at: Time.current)
  end

  private
    def sync(sync, upload)
      return unless upload.status == "applying" && upload.gateway_id == sync.source.id

      sync.source.with_upload(upload) { sync.full }
      upload.update!(status: "applied", applied_at: Time.current)
    rescue StandardError
      upload.update_columns(status: "previewed")
      raise
    end
end
