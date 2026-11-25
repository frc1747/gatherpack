# Applies an uploaded file to its file source: the source's records are
# replaced with the file's, and records the file no longer has are marked
# deleted. An upload that doesn't finish goes back to its preview.
class Accounting::ApplyUploadJob < Accounting::SyncJob
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
