# Once a day: one message to each manager with registration applications
# waiting in the teams they manage, "<n> people are waiting to join <team>."
# per team. A manager gets at most one a day, even if the job runs twice.
# Admins count as managing every team, unless the site limits admins to their
# own roles; then they hear only about teams they manage and teams with no
# manager. Runs from config/recurring.yml while the feature is on.
class Intake::DigestJob < ApplicationJob
  queue_as :default

  def perform(today = Date.current)
    return unless Intake.enabled?
    counts = MembershipApplication.pending.where.not(registration_id: nil).group(:team_id).count
    return if counts.empty?

    teams = Team.where(id: counts.keys).index_by(&:id)
    store = Intake.rate_limit_store || Rails.cache
    unmanaged_ids = Intake::Notices.admins_everywhere? ? [] : teams.values.select { |team| team.all_managers.empty? }.map(&:id)
    recipients = Person.where(id: Membership.where(manager: true).select(:person_id))
    recipients = recipients.or(Person.where(id: Intake::Notices.admins.select(:id))) if unmanaged_ids.any?
    recipients.includes(:user).find_each do |manager|
      next if manager.user&.email.blank?
      ids = team_ids_for(manager, counts.keys, unmanaged_ids)
      next if ids.empty?
      next unless store.write("intake-digest:#{manager.id}:#{today.iso8601}", true, expires_in: 2.days, unless_exist: true)

      lines = ids.map { |id| teams[id] }.sort_by(&:name).map do |team|
        count = counts[team.id]
        "#{count} #{count == 1 ? "person is" : "people are"} waiting to join #{team.name}."
      end
      Intake::Notices.digest(manager, lines)
    end
  end

  private

  # The teams with people waiting that this person's message lists.
  def team_ids_for(person, waiting_ids, unmanaged_ids)
    return person.all_managed_teams.where(id: waiting_ids).pluck(:id) if Intake::Notices.admins_everywhere?
    ids = person.notice_teams.where(id: waiting_ids).pluck(:id)
    person.admin? ? ids | unmanaged_ids : ids
  end
end
