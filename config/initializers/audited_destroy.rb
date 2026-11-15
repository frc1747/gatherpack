Rails.application.config.to_prepare do
  ApplicationRecord.include(AuditedDestroy)
end
