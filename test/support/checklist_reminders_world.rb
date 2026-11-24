require_relative "checklists_world"

# Checklist reminders on top of the checklists world (see checklists_world):
# reminders, checklists and person fields switched on, a profile field
# helper, and the emails a send queued.
module ChecklistRemindersWorld
  include ChecklistsWorld
  include ActiveJob::TestHelper

  # Turns ReminderDigest.delivery_for into a fixed answer for a block, where
  # the summaries seam may not exist.
  module DigestOverride
    class << self
      attr_accessor :delivery
    end

    def delivery_for(person)
      DigestOverride.delivery || super
    end
  end
  Checklists::ReminderDigest.singleton_class.prepend(DigestOverride)

  # Turns Features.enabled?(:digests) into a fixed answer for a block.
  module SummariesOverride
    class << self
      attr_accessor :enabled
    end

    def enabled?(key)
      key == :digests && !SummariesOverride.enabled.nil? ? SummariesOverride.enabled : super
    end
  end
  GatherPack::Features.singleton_class.prepend(SummariesOverride)

  def with_reminders(**settings, &block)
    with_settings(feature_checklists: "true", feature_checklist_reminders: "true", feature_person_fields: "true", **settings, &block)
  end

  def with_digest_delivery(delivery)
    DigestOverride.delivery = delivery
    yield
  ensure
    DigestOverride.delivery = nil
  end

  # Stands in for the summaries seam (GatherPack::Digests) and the Summaries
  # setting for a block, where the seam may not be merged. While on, everyone
  # chose the summary (:daily) for checklist reminders, with or without the
  # real seam; while off, delivery is left to ReminderDigest (plain email).
  def with_summaries(enabled)
    added = !GatherPack.const_defined?(:Digests, false)
    if added
      GatherPack.const_set(:Digests, Module.new do
        def self.handles?(_key) = true
        def self.delivery_for(_key, _person) = :daily
      end)
    end
    SummariesOverride.enabled = enabled
    enabled ? with_digest_delivery(:daily) { yield } : yield
  ensure
    SummariesOverride.enabled = nil
    GatherPack.send(:remove_const, :Digests) if added
  end

  def create_field(name, data_type = :string, **attributes)
    PersonField.create!({ name: name, data_type: data_type, read_permission: "admin", write_permission: "admin" }.merge(attributes))
  end

  # [[address, subject, body], ...] of the reminder emails queued.
  def sent_emails
    enqueued_jobs.select { |job| job["job_class"] == "SendEmailJob" }.map { |job| job["arguments"][1..3] }
  end

  def emails_to(name)
    sent_emails.select { |address, _, _| address == person(name).user.email }
  end

  def request_for(checklist, **options)
    Checklists::ReminderSender::Request.new(checklist: checklist, **options)
  end
end
