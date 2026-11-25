# Nightly: every enabled rule evaluated for everyone (milestones pass
# without any record changing), and on Sundays a full read of every
# connected source, as a backstop for anything the change feed and
# notifications missed.
class Accounting::NightlyJob < ApplicationJob
  queue_as :default

  def perform
    return unless Accounting.enabled?

    AccountingRule.enabled.find_each { |rule| Accounting::EvaluateRuleJob.perform_later(rule) }
    if Date.current.sunday?
      Accounting.sources.each { |source| Accounting::FullSyncJob.perform_later(source) if source.syncable? }
    end
  end
end
