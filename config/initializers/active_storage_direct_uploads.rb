# Direct uploads need a signed-in user and stay within the attachment limits;
# see DirectUploadRestrictions.
Rails.application.config.to_prepare do
  ActiveStorage::DirectUploadsController.include DirectUploadRestrictions
end
