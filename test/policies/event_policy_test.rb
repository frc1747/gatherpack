require "test_helper"

class EventPolicyTest < ActiveSupport::TestCase
  def test_scope
  end

  def test_show
  end

  def test_create
  end

  def test_update
  end

  def test_destroy
  end

  test "show? agrees with the scope" do
    # Org (run by org_leader)
    # ├── Team A (student, lead_a)
    # │   └── Team A Jr
    # └── Team B
    # Other Org
    org = Team.create!(name: "Org", team_type: team_types(:one))
    team_a = Team.create!(name: "Team A", team_type: team_types(:one), parent: org)
    team_a_jr = Team.create!(name: "Team A Jr", team_type: team_types(:one), parent: team_a)
    team_b = Team.create!(name: "Team B", team_type: team_types(:one), parent: org)
    other_org = Team.create!(name: "Other Org", team_type: team_types(:one))

    events = [ org, team_a, team_a_jr, team_b, other_org, nil ].map do |team|
      Event.create!(name: "#{team&.name || "No team"} event", start_time: 1.day.from_now, event_type: event_types(:one), team: team)
    end
    viewers = {
      student: create_user("student", team: team_a),
      lead_a: create_user("lead-a", team: team_a, manager: true),
      org_leader: create_user("org-leader", team: org, manager: true),
      outsider: create_user("outsider", team: other_org),
      admin: create_user("admin", admin: true)
    }

    viewers.each do |name, user|
      in_scope = EventPolicy::Scope.new(user, Event).resolve.where(id: events.map(&:id)).to_a
      events.each do |event|
        assert_equal in_scope.include?(event), EventPolicy.new(user, event).show?,
          "#{name}: show? and the scope disagree about #{event.name}"
      end
    end

    student_sees = EventPolicy::Scope.new(viewers[:student], Event).resolve.where(id: events.map(&:id))
    assert_equal [ "Org event", "Team A event" ], student_sees.map(&:name).sort
    assert_not EventPolicy.new(viewers[:student], events[3]).show?, "a student opened a sibling team's event"
    assert_not EventPolicy.new(viewers[:student], events[4]).show?, "a student opened another organization's event"
    assert EventPolicy.new(viewers[:lead_a], events[2]).show?, "a manager couldn't open their sub-team's event"
    assert EventPolicy.new(viewers[:admin], events[5]).show?, "an admin couldn't open an event with no team"
  end

  private

  def create_user(name, team: nil, manager: false, admin: false)
    user = User.create!(email: "#{name}@example.com", password: "Password1!", admin: admin)
    person = Person.create!(user: user, first_name: name.capitalize, last_name: "Test")
    Membership.create!(person: person, team: team, manager: manager) if team
    user
  end
end
