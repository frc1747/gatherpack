require "test_helper"
require_relative "../support/forms_world"
require_relative "../support/settings_test_helper"

# The Audience tab's team picker offers exactly what FormAudienceRulePolicy
# allows, through FormPolicy#audience_teams. Form creators can also ask the
# teams named in forms_creator_extra_audience_teams, but never own them.
class FormAudienceTeamsTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers
  include FormsWorld
  include SettingsTestHelper

  setup do
    host! "localhost"
    build_person_fields_world
    @creator_badge = create_world_badge("Student Leader")
    BadgeAssignment.create!(badge: @creator_badge, person: person(:a1))
    @mentors = Team.create!(name: "Mentors", team_type: team_types(:one), parent: @org)
    @mentor_subteam = Team.create!(name: "Mentor Drivers", team_type: team_types(:one), parent: @mentors)
    @event = Event.create!(name: "Den A Pizza Night", event_type: event_types(:one), team: @den_a, start_time: 3.days.from_now)
    @staff_form = create_world_form("Staff Poll", team: @den_a, include: [ @den_a ], event: @event, created_by: person(:den_a_leader))
    @own = create_world_form("Pizza Poll", team: @den_a, include: [ @den_a ], event: @event, created_by: person(:a1))
  end

  test "a creator with no managed teams can ask a creator team, not an unrelated one" do
    with_creators do
      assert_empty person(:a1).all_managed_teams
      assert_equal [ @den_a ], audience_teams(:a1)
      assert allowed?(:a1, @den_a)
      assert_not allowed?(:a1, @den_b)
      assert_not allowed?(:a1, @other_org)
    end
  end

  test "teams named in the setting, and those below, can be asked only once it is set" do
    with_creators do
      assert_not allowed?(:a1, @mentors)
      assert_not allowed?(:a1, @mentor_subteam)

      with_settings(forms_creator_extra_audience_teams: "other thing\n mentors \n") do
        assert allowed?(:a1, @mentors)
        assert allowed?(:a1, @mentor_subteam)
        assert_not allowed?(:a1, @den_b)
        assert_equal [ @den_a, @mentor_subteam, @mentors ].map(&:id).sort, audience_teams(:a1).ids.sort
      end
    end
  end

  test "a team from the setting can't be the form's owning team" do
    with_creators do
      with_settings(forms_creator_extra_audience_teams: "Mentors") do
        assert_not_includes FormPolicy.new(person(:a1).user, @own).assignable_teams, @mentors
        assert_not FormPolicy.new(person(:a1).user, Form.new(team: @mentors, event: @event)).create?
      end
    end
  end

  test "the setting only reaches the forms a creator runs as its creator" do
    with_creators do
      with_settings(forms_creator_extra_audience_teams: "Mentors") do
        assert_not_includes audience_teams(:a1, form: @staff_form), @mentors
      end
    end
  end

  test "a creator sees their teams and the setting's teams in the picker" do
    with_creators do
      as(:a1) do
        get edit_form_path(@own, tab: "audience")
        assert_select "#audience select[name='form_audience_rule[team_id]'] option", text: "Den A"
        assert_select "#audience select[name='form_audience_rule[team_id]'] option", text: "Mentors", count: 0
        assert_select "#audience select[name='form_audience_rule[team_id]'] option", text: "Den B", count: 0
        with_settings(forms_creator_extra_audience_teams: "Mentors") do
          get edit_form_path(@own, tab: "audience")
          assert_select "#audience select[name='form_audience_rule[team_id]'] option", text: "Mentors"
          assert_select "#audience select[name='form_audience_rule[team_id]'] option", text: "Mentor Drivers"

          post form_audience_rules_path(@own), params: { form_audience_rule: { effect: "include", target_type: "team", team_id: @mentors.id } }
          assert @own.form_audience_rules.exists?(team: @mentors)
        end
      end
    end
  end

  test "a manager sees their managed teams and an admin sees every team" do
    with_settings(feature_forms: "true") do
      form = create_world_form("Den Poll", team: @den_a, include: [ @den_a ])
      as(:den_a_leader) do
        get edit_form_path(form, tab: "audience")
        assert_select "#audience select[name='form_audience_rule[team_id]'] option", text: "Den A"
        assert_select "#audience select[name='form_audience_rule[team_id]'] option", text: "Den B", count: 0
      end
      as(:admin) do
        get edit_form_path(form, tab: "audience")
        assert_select "#audience select[name='form_audience_rule[team_id]'] option", text: "Other Org"
      end
    end
  end

  test "a creator with nothing to add sees No teams you can add" do
    with_creators do
      loner = create_world_person("Loner")
      BadgeAssignment.create!(badge: @creator_badge, person: loner)
      form = Form.create!(title: "Loner Poll", team: @den_a, event: @event, created_by: loner, respond_permission: "family", read_permission: "family", status: :draft)
      @people[:loner] = loner
      assert_empty audience_teams(:loner, form: form)
      as(:loner) do
        get edit_form_path(form, tab: "audience")
        assert_response :success
        assert_select "#no_audience_teams", text: "No teams you can add"
        assert_select "select[name='form_audience_rule[team_id]']", count: 0
      end
    end
  end

  test "the picker lists exactly the teams the policy allows" do
    with_creators do
      with_settings(forms_creator_extra_audience_teams: "Mentors") do
        Team.all.each do |team|
          rule = FormAudienceRule.new(form: @own, target_type: :team, team: team, effect: :include)
          assert_equal audience_teams(:a1).exists?(id: team.id), FormAudienceRulePolicy.new(person(:a1).user, rule).create?, team.name
        end
      end
    end
  end

  private

  def audience_teams(name, form: @own)
    FormPolicy.new(person(name).user, form).audience_teams
  end

  def allowed?(name, team)
    rule = FormAudienceRule.new(form: @own, target_type: :team, team: team, effect: :include)
    FormAudienceRulePolicy.new(person(name).user, rule).create?
  end

  def with_creators(&block)
    with_settings(feature_forms: "true", forms_creator_badge: "student leader", &block)
  end

  def as(name)
    sign_in person(name).user
    yield
  ensure
    sign_out :user
  end
end
