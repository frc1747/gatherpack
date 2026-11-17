require "test_helper"
require_relative "../support/signups_world"

# Organizers open a sheet to people and badges only within their reach:
# the teams they may create sheets for and the sheet's own teams
# (SignupSheet#reach_team_ids). worker organizes the Club sheet with a
# badge capped at Club; outsider is in Other Org, out of reach.
class SignupAudienceReachTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers
  include ActiveJob::TestHelper
  include SignupsWorld

  setup do
    host! "localhost"
    build_signups_world
    @restore_settings = apply_settings(signups_organizers: "Sheet Organizer > Club")
    @sheet = create_world_sheet(created_by: person(:worker))
    @position = @sheet.signup_positions.create!(name: "Cashier", capacity: 5)
  end

  teardown { @restore_settings&.call }

  test "an organizer can't add a person outside their reach to the sheet's audience" do
    sign_in person(:worker).user
    assert_not SignupSheet.creatable_team_ids(person(:worker)).include?(@other_org.id)

    assert_no_difference "SignupAudienceRule.count" do
      post signup_sheet_signup_audience_rules_path(@sheet),
        params: { signup_audience_rule: { effect: "include", target_type: "person", person_id: person(:outsider).id } }
    end
    assert_equal "Pick someone in your teams or the sheet's.", flash[:alert]
    assert_not @sheet.reload.open_to?(person(:outsider))
  end

  test "an organizer can't place and message someone outside their reach" do
    sign_in person(:worker).user
    post signup_sheet_signup_audience_rules_path(@sheet),
      params: { signup_audience_rule: { effect: "include", target_type: "person", person_id: person(:outsider).id } }
    post signup_sheet_roster_signups_path(@sheet),
      params: { signup: { signup_slot_id: slot_for(@position).id, person_id: person(:outsider).id } }
    post signup_sheet_signup_messages_path(@sheet), params: { event_id: @event.id, subject: "Hi", body: "Practice moved" }

    assert_not Signup.exists?(person: person(:outsider))
    assert_not_includes enqueued_email_addresses, email_of(:outsider)
  end

  test "an organizer can't open their sheet to a team-less badge's holders outside their reach" do
    other_badge = create_world_badge("Other Org Badge")
    BadgeAssignment.create!(badge: other_badge, person: person(:outsider))
    BadgeAssignment.create!(badge: other_badge, person: person(:student2))
    sign_in person(:worker).user

    assert_difference "SignupAudienceRule.count" do
      post signup_sheet_signup_audience_rules_path(@sheet),
        params: { signup_audience_rule: { effect: "include", target_type: "badge", badge_id: other_badge.id } }
    end

    assert_not @sheet.reload.open_to?(person(:outsider))
    assert @sheet.open_to?(person(:student2)), "holders within reach are covered"
  end

  test "an organizer can't add a badge of a team outside their reach" do
    other_badge = create_world_badge("Other Org Team Badge", team: @other_org)
    sign_in person(:worker).user

    assert_no_difference "SignupAudienceRule.count" do
      post signup_sheet_signup_audience_rules_path(@sheet),
        params: { signup_audience_rule: { effect: "include", target_type: "badge", badge_id: other_badge.id } }
    end
    assert_equal "Pick a badge in your teams or the sheet's.", flash[:alert]
  end

  test "an organizer adds a team, a person and a badge within reach" do
    concessions_badge = create_world_badge("Grill Crew", team: @concessions)
    BadgeAssignment.create!(badge: concessions_badge, person: person(:concessions_manager))
    sign_in person(:worker).user

    assert_difference "SignupAudienceRule.count", 3 do
      post signup_sheet_signup_audience_rules_path(@sheet), params: { signup_audience_rule: { effect: "include", target_type: "team", team_id: @students.id } }
      post signup_sheet_signup_audience_rules_path(@sheet), params: { signup_audience_rule: { effect: "include", target_type: "person", person_id: person(:worker).id } }
      post signup_sheet_signup_audience_rules_path(@sheet), params: { signup_audience_rule: { effect: "include", target_type: "badge", badge_id: concessions_badge.id } }
    end
    assert_equal [ person(:worker) ], @sheet.signup_audience_rules.map(&:created_by).uniq
    %i[ student student2 worker concessions_manager ].each { |name| assert @sheet.reload.open_to?(person(name)), name }
    assert_not @sheet.open_to?(person(:outsider))
  end

  test "an organizer may exclude anyone" do
    sign_in person(:worker).user

    assert_difference "SignupAudienceRule.count" do
      post signup_sheet_signup_audience_rules_path(@sheet),
        params: { signup_audience_rule: { effect: "exclude", target_type: "person", person_id: person(:outsider).id } }
    end
  end

  test "an admin adds anyone and any badge" do
    other_badge = create_world_badge("Other Org Team Badge", team: @other_org)
    sibling_badge = create_world_badge("Sibling Badge")
    BadgeAssignment.create!(badge: sibling_badge, person: person(:sibling))
    sign_in person(:admin).user

    assert_difference "SignupAudienceRule.count", 3 do
      post signup_sheet_signup_audience_rules_path(@sheet), params: { signup_audience_rule: { effect: "include", target_type: "person", person_id: person(:outsider).id } }
      post signup_sheet_signup_audience_rules_path(@sheet), params: { signup_audience_rule: { effect: "include", target_type: "badge", badge_id: other_badge.id } }
      post signup_sheet_signup_audience_rules_path(@sheet), params: { signup_audience_rule: { effect: "include", target_type: "badge", badge_id: sibling_badge.id } }
    end
    assert @sheet.reload.open_to?(person(:outsider))
    assert @sheet.open_to?(person(:sibling)), "a team-less badge an admin added covers everyone holding it"
  end

  test "a person rule with no recorded creator only covers the sheet's teams" do
    @sheet.signup_audience_rules.create!(effect: :include, target_type: :person, person: person(:outsider))
    @sheet.signup_audience_rules.create!(effect: :include, target_type: :person, person: person(:student))

    assert_not @sheet.open_to?(person(:outsider))
    assert @sheet.open_to?(person(:student))
  end

  test "a rule stops reaching people when its creator's reach shrinks" do
    @sheet.signup_audience_rules.create!(effect: :include, target_type: :person, person: person(:outsider), created_by: person(:admin))
    assert @sheet.open_to?(person(:outsider))

    person(:admin).user.update!(admin: false)
    assert_not SignupSheet.find(@sheet.id).open_to?(person(:outsider))
  end

  test "the pickers offer only people and badges in reach" do
    create_world_badge("Other Org Team Badge", team: @other_org)
    create_world_badge("Grill Crew", team: @concessions)
    sign_in person(:worker).user

    get edit_signup_sheet_path(@sheet)
    assert_response :success
    assert_select "#audience select[name='signup_audience_rule[person_id]']" do
      assert_select "option", text: person(:student).display_name
      assert_select "option", text: person(:outsider).display_name, count: 0
    end
    assert_select "#audience select[name='signup_audience_rule[badge_id]']" do
      assert_select "option", text: "Grill Crew"
      assert_select "option", text: "Alcohol License"
      assert_select "option", text: "Other Org Team Badge", count: 0
    end

    sign_in person(:admin).user
    get edit_signup_sheet_path(@sheet)
    assert_select "#audience select[name='signup_audience_rule[person_id]']", count: 0
    assert_select "#audience select[name='signup_audience_rule[badge_id]'] option", text: "Other Org Team Badge"
  end
end
