require "gatherpack/recurring_schedule"

Rails.application.config.to_prepare do
  unless SolidQueue::Configuration.ancestors.include?(GatherPack::RecurringSchedule::ConfigurationExtension)
    SolidQueue::Configuration.prepend(GatherPack::RecurringSchedule::ConfigurationExtension)
  end
end
