# Forms whose responses expire on a date or some months after signing.
Rails.application.config.to_prepare do
  Form.include(Forms::Expiry)
  FormResponse.prepend(Forms::ResponseExpiry)
end
