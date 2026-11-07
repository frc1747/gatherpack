module Housekeeping
  # "Move selected to another team": each person's membership of one team
  # is replaced by one of another (an alumni team, say), after a preview.
  # A manager of both teams acts; nothing is automatic. Only direct members
  # move, and managers stay put (take that off first), so nobody loses a
  # role by accident.
  #
  #   move = Housekeeping::MovePeople.new(from: team, to: alumni, people: people)
  #   move.sentence   # "3 people will move from Club to Alumni. 1 skipped."
  #   move.apply!     # => the people moved
  class MovePeople
    attr_reader :from, :to, :ready, :skipped

    def initialize(from:, to:, people:)
      @from = from
      @to = to
      @ready = []
      @skipped = []
      memberships = from.memberships.where(person_id: people.map(&:id)).index_by(&:person_id)
      people.each do |person|
        reason = skip_reason(memberships[person.id])
        reason ? @skipped << Preview::Skip.new(person, reason) : @ready << person
      end
    end

    # Admins, and people who manage both teams.
    def self.allowed?(user, from, to)
      user.admin? || (from.manager?(user.person) && to.manager?(user.person))
    end

    def sentence
      text = "#{ready.size} #{ready.size == 1 ? "person" : "people"} will move from #{from.name} to #{to.name}."
      text += " #{skipped.size} skipped." if skipped.any?
      text
    end

    def apply!
      Membership.transaction do
        ready.each do |person|
          to.memberships.find_or_create_by!(person: person)
          from.memberships.find_by(person: person)&.destroy!
        end
      end
      ready
    end

    private

    def skip_reason(membership)
      return "not a direct member of #{from.name}" if membership.nil?

      "manages #{from.name}" if membership.manager?
    end
  end
end
