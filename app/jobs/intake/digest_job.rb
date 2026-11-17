# Once a day: one message to each manager with registration applications
# waiting in the teams they manage, "<n> people are waiting to join <team>."
# per team. A manager gets at most one a day, even if the job runs twice.
# Runs from config/recurring.yml while the feature is on.
class Intake::DigestJob < ApplicationJob
  queue_as :default

  def perform(today = Date.current)
    return unless Intake.enabled?
    counts = MembershipApplication.pending.where.not(registration_id: nil).group(:team_id).count
    return if counts.empty?

    teams = Team.where(id: counts.keys).index_by(&:id)
    store = Intake.rate_limit_store || Rails.cache
    Person.joins(:memberships).where(memberships: { manager: true }).distinct.includes(:user).find_each do |manager|
      next if manager.user&.email.blank?
      ids = manager.all_managed_teams.where(id: counts.keys).pluck(:id)
      next if ids.empty?
      next unless store.write("intake-digest:#{manager.id}:#{today.iso8601}", true, expires_in: 2.days, unless_exist: true)

      lines = ids.map { |id| teams[id] }.sort_by(&:name).map do |team|
        count = counts[team.id]
        "#{count} #{count == 1 ? "person is" : "people are"} waiting to join #{team.name}."
      end
      Intake::Notices.digest(manager, lines)
    end
  end
end
