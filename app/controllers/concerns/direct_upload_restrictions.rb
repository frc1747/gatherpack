# Active Storage draws its direct-upload endpoint for every app, and it takes
# no sign-in: anyone could create blobs and write files of any size and type
# to the storage service. The app's forms don't use direct uploads, but the
# endpoint stays usable by signed-in users, within the limits the app's own
# attachments accept. The follow-up upload (the PUT to the service URL) is
# signed for the blob created here, so guarding this action covers it.
#
# Included into ActiveStorage::DirectUploadsController by
# config/initializers/active_storage_direct_uploads.rb.
module DirectUploadRestrictions
  extend ActiveSupport::Concern

  MAX_BYTE_SIZE = 10.megabytes
  CONTENT_TYPES = (AttachmentValidator::IMAGE_TYPES + %w[application/pdf]).freeze

  included do
    before_action :require_signed_in_user
    before_action :check_blob_limits
  end

  private

  def require_signed_in_user
    render json: { error: "You must be signed in to upload files" }, status: :unauthorized unless user_signed_in?
  end

  def check_blob_limits
    blob = params.expect(blob: [ :byte_size, :content_type ])

    if blob[:byte_size].to_i > MAX_BYTE_SIZE
      render json: { error: "File is too large (maximum is #{MAX_BYTE_SIZE / 1.megabyte} MB)" }, status: :unprocessable_entity
    elsif CONTENT_TYPES.exclude?(blob[:content_type])
      render json: { error: "File type is not allowed" }, status: :unprocessable_entity
    end
  end
end
