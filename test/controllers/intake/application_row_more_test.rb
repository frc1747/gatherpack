require "test_helper"
require_relative "../../support/intake_world"

# Intake's row actions on the application pages: upstream's View, Approve and
# Deny stay as they are; Link, Keep separate and Delete as spam sit in a small
# More menu on the row.
class Intake::ApplicationRowMoreTest < ActionDispatch::IntegrationTest
  include IntakeWorld
  include Devise::Test::IntegrationHelpers

  setup do
    host! "localhost"
    build_intake_world
    @placeholder = Person.create!(first_name: "Riley", last_name: "Rivera")
    Membership.create!(person: @placeholder, team: @everyone)
    @riley = create_intake_person("Riley", "Rivera", email: "riley@example.com", birthday: 30.years.ago.to_date)
    @entry = @registration.entries.create!(first_name: "Riley", last_name: "Rivera", person: @riley, verified_at: Time.current,
      facts: { "team_ids" => [ @juniors.id ] })
    @member = Intake::Enrollment.new(@entry).applicant_member!(@riley)
    Intake::Enrollment.new(@entry).apply(@riley)
    @application = @riley.membership_applications.sole
    sign_in @leader.user
  end

  test "a flagged match row keeps upstream's buttons and puts Link and Keep separate in a More" do
    with_intake { get applications_team_path(@juniors) }

    assert_select "a.btn.btn-sm.btn-outline-primary", text: "View"
    assert_select "a.btn.btn-sm.btn-success[href=?]", team_membership_application_path(@juniors, @application, status: "approved"), text: "Approve"
    assert_select "a.btn.btn-sm.btn-danger[href=?]", team_membership_application_path(@juniors, @application, status: "denied"), text: "Deny"
    assert_select "input.btn.btn-sm.btn-danger[value=?]", "Deny with reason"
    assert_select "#intake_#{dom_id(@application)} .badge", text: /Might be the same person as/
    assert_select "#intake_#{dom_id(@application)} .dropdown" do
      assert_select "button.btn.btn-sm.btn-outline-secondary.dropdown-toggle", text: "More"
      assert_select ".dropdown-menu form[action=?] button.dropdown-item", link_intake_registration_match_path(@registration, @member), text: "Link"
      assert_select ".dropdown-menu form[action=?] button.dropdown-item", keep_separate_intake_registration_match_path(@registration, @member), text: "Keep separate"
    end
    assert_select "#intake_#{dom_id(@application)} > div > form button", text: /Link|Keep separate/, count: 0
  end

  test "Keep separate from the More clears the flag and the menu" do
    with_intake do
      get applications_team_path(@juniors)
      post css_select("#intake_#{dom_id(@application)} .dropdown-menu form").detect { |form| form.text.include?("Keep separate") }["action"]
      assert_nil @member.reload.possible_match

      get applications_team_path(@juniors)
      assert_select "#intake_#{dom_id(@application)} .dropdown", 0
    end
  end

  test "Link from the More links the sign-up to the person on file" do
    with_intake do
      get applications_team_path(@juniors)
      post css_select("#intake_#{dom_id(@application)} .dropdown-menu form").detect { |form| form.text.include?("Link") }["action"]
    end

    assert_equal "Linked to Riley Rivera.", flash[:notice]
    assert_equal @placeholder, @member.reload.person
  end

  test "an admin finds Delete as spam last in a denied row's More" do
    spammer = create_intake_person("Sam", "Spammer", birthday: 30.years.ago.to_date)
    spam = MembershipApplication.create!(person: spammer, team: @juniors, registration: @registration, source: :link)
    spam.deny!
    sign_in @admin.user
    with_intake { get team_membership_applications_path(@juniors) }

    assert_select "#intake_#{dom_id(spam)} .dropdown .dropdown-menu li:last-child a.dropdown-item.text-danger[href=?]",
      intake_spam_person_path(spammer), text: "Delete as spam"
    assert_select "#intake_#{dom_id(spam)} > a.btn", 0
  end
end
