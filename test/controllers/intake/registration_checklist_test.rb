require "test_helper"
require_relative "../../support/intake_world"

# A registration's checklist: the panel on /join/:slug/me for applicants and
# their guardians, the counts beside applications, the approval gate and
# bulk decisions.
class Intake::RegistrationChecklistTest < ActionDispatch::IntegrationTest
  include IntakeWorld
  include ActiveJob::TestHelper
  include Devise::Test::IntegrationHelpers

  setup do
    host! "localhost"
    build_intake_world
    @checklist = Checklist.create!(title: "Joining", team: @northwind, status: :active, starts_on: 1.month.ago.to_date,
      ends_on: 1.year.from_now.to_date, created_by: @leader)
    @checklist.checklist_rules.create!(effect: :include, target_type: :applicants, team: @juniors)
    @checklist.checklist_rules.create!(effect: :include, target_type: :team, team: @juniors)
    @login = add_item("Login", :has_login)
    @agreement = add_item("Team agreement", :attested, "statement" => "Agreement signed", "attested_by" => "guardian")
    @registration.update!(checklist: @checklist)

    @applicant = create_intake_person("Riley", "Rivera", birthday: 30.years.ago.to_date)
    @application = MembershipApplication.create!(person: @applicant, team: @juniors, registration: @registration, source: :link)
  end

  def add_item(label, kind, config = {})
    item = @checklist.checklist_items.new(kind: kind.to_s, label: label)
    item.config_params = config
    item.save!
    item
  end

  def with_checklists(extra = {}, &block)
    with_intake({ feature_checklists: "true" }.merge(extra), &block)
  end

  def attest(person, by: person)
    ChecklistAttestation.create!(person: person, key: @agreement.config["key"], statement: "Agreement signed", attested_by: by, attested_as: "guardian")
  end

  def refresh
    Checklists::Refresher.new(@checklist.reload).call
  end

  # Bodies of the emails queued by the block.
  def queued_email_bodies
    before = enqueued_jobs.size
    yield
    enqueued_jobs.drop(before).select { |job| job[:job] == SendEmailJob }.map { |job| job[:args].last }
  end

  test "an applicant on no team is covered and sees their checklist on their registration page" do
    sign_in @applicant.user
    with_checklists { get intake_me_path(@registration.slug) }

    assert_response :success
    assert_select "##{ActionView::RecordIdentifier.dom_id(@applicant, :intake_checklist)}" do
      assert_select "h2", "Your checklist"
      assert_select "li", text: /Team agreement/
      assert_select "button", "I confirm"
    end
  end

  test "nothing about the checklist shows while the checklists feature is off" do
    sign_in @applicant.user
    with_intake { get intake_me_path(@registration.slug) }

    assert_response :success
    assert_no_match "Your checklist", response.body
  end

  test "a guardian sees their ward's checklist and confirms for them" do
    ward = create_intake_person("Kit", "Rivera", birthday: 12.years.ago.to_date)
    guardian = create_intake_person("Gale", "Rivera", birthday: 40.years.ago.to_date)
    Relationship.create!(parent: guardian, child: ward, relationship_type: @parent_of, created_by: @admin)
    MembershipApplication.create!(person: ward, team: @juniors, registration: @registration, source: :link)
    sign_in guardian.user

    with_checklists do
      get intake_me_path(@registration.slug)
      assert_select "##{ActionView::RecordIdentifier.dom_id(ward, :intake_checklist)}" do
        assert_select "h2", "Kit's checklist"
        assert_select "button", "Confirm for Kit"
      end

      post checklist_checklist_attestations_path(@checklist, item_id: @agreement.id, person_id: ward.id),
        headers: { "HTTP_REFERER" => intake_me_url(@registration.slug) }
    end

    assert_redirected_to intake_me_url(@registration.slug)
    assert ChecklistAttestation.exists?(person: ward, attested_by: guardian)
  end

  test "someone unrelated can't confirm for another applicant, and their page doesn't show them" do
    stranger = create_intake_person("Sam", "Stone", birthday: 40.years.ago.to_date)
    MembershipApplication.create!(person: stranger, team: @juniors, registration: @registration, source: :link)
    sign_in stranger.user

    with_checklists do
      get intake_me_path(@registration.slug)
      assert_select "##{ActionView::RecordIdentifier.dom_id(@applicant, :intake_checklist)}", count: 0

      post checklist_checklist_attestations_path(@checklist, item_id: @agreement.id, person_id: @applicant.id)
    end

    assert_not ChecklistAttestation.exists?(person: @applicant)
  end

  test "managers see checklist counts and what's missing beside the application" do
    sign_in @leader.user
    with_checklists { get applications_team_path(@juniors) }

    assert_response :success
    assert_select "##{ActionView::RecordIdentifier.dom_id(@application, :intake_checklist)}" do
      assert_select "summary", text: /1 of 2 done/
      assert_select "summary", text: /waiting for Team agreement/
    end
  end

  test "a gated registration holds approval until the checklist is done" do
    @registration.update!(gate_approval: true)
    sign_in @leader.user

    with_checklists { patch team_membership_application_path(@juniors, @application), params: { status: "approved" } }
    assert @application.reload.pending?
    assert_equal "Riley hasn't finished Joining.", flash[:alert]

    attest(@applicant)
    with_checklists { patch team_membership_application_path(@juniors, @application), params: { status: "approved" } }
    assert @application.reload.approved?
    assert_equal({ "id" => @checklist.id, "title" => "Joining", "status" => "met" }, @application.intake_placement["checklist"])
  end

  test "approval doesn't wait for the checklist unless the registration says so" do
    sign_in @leader.user
    with_checklists { patch team_membership_application_path(@juniors, @application), params: { status: "approved" } }

    assert @application.reload.approved?
    assert_equal "not_met", @application.intake_placement.dig("checklist", "status")
  end

  test "approve! refuses a gated application whatever calls it" do
    @registration.update!(gate_approval: true)

    with_checklists do
      error = assert_raises(Intake::ApprovalGate::Blocked) { @application.approve! }
      assert_equal "Riley hasn't finished Joining.", error.message
    end
    assert @application.reload.pending?
  end

  test "someone the checklist doesn't cover can't pass the gate" do
    @registration.update!(gate_approval: true)
    mentor = create_intake_person("Mo", "Mentor", birthday: 40.years.ago.to_date)
    application = MembershipApplication.create!(person: mentor, team: @mentors, registration: @registration, source: :link)

    with_checklists { assert_equal "Joining doesn't cover Mo.", Intake::ApprovalGate.new(application).reason }
  end

  test "bulk approve skips rows whose checklist isn't done and says why" do
    @registration.update!(gate_approval: true)
    done = create_intake_person("Dana", "Done", birthday: 30.years.ago.to_date)
    done_application = MembershipApplication.create!(person: done, team: @juniors, registration: @registration, source: :link)
    attest(done)
    sign_in @leader.user

    with_checklists do
      post intake_team_bulk_decisions_path(@juniors), params: { decision: "approved", application_ids: [ @application.id, done_application.id ] }
    end

    assert_redirected_to applications_team_path(@juniors)
    assert done_application.reload.approved?
    assert @application.reload.pending?
    assert_equal "Approved 1.", flash[:notice]
    assert_equal "Skipped: Riley Rivera (checklist not done).", flash[:alert]
    assert_includes done.teams, @everyone
  end

  test "bulk approve skips a row that needs a team picked, and one that's the manager's own relative's" do
    @registration.update!(pick_one_required: true)
    relative = create_intake_person("Rae", "Leader", birthday: 30.years.ago.to_date)
    sibling_of = RelationshipType.create!(parent_label: "Sibling of", child_label: "Sibling of", permission: :added_by_admin, guardianship: :none)
    Relationship.create!(parent: @juniors_leader, child: relative, relationship_type: sibling_of, created_by: @admin)
    relative_application = MembershipApplication.create!(person: relative, team: @juniors, registration: @registration, source: :link)
    sign_in @juniors_leader.user

    with_checklists do
      post intake_team_bulk_decisions_path(@juniors), params: { decision: "approved", application_ids: [ @application.id, relative_application.id ] }
    end

    assert @application.reload.pending?
    assert relative_application.reload.pending?
    assert_equal "Skipped: Riley Rivera (choose a team); Rae Leader (yours or a relative's).", flash[:alert]
  end

  test "bulk deny keeps the reason on each and sends it" do
    other = create_intake_person("Oli", "Other", birthday: 30.years.ago.to_date)
    other_application = MembershipApplication.create!(person: other, team: @juniors, registration: @registration, source: :link)
    sign_in @leader.user

    with_checklists do
      assert_enqueued_jobs 2, only: SendEmailJob do
        post intake_team_bulk_decisions_path(@juniors), params: { decision: "denied", reason: "We're full.", application_ids: [ @application.id, other_application.id ] }
      end
    end

    assert_equal "Denied 2.", flash[:notice]
    assert [ @application, other_application ].all? { |application| application.reload.denied? && application.reviewer_notes == "We're full." }
  end

  test "bulk decisions need someone who can review the team" do
    sign_in @applicant.user
    with_checklists { post intake_team_bulk_decisions_path(@juniors), params: { decision: "approved", application_ids: [ @application.id ] } }

    assert @application.reload.pending?
  end

  test "the team's page has the bulk form and a tick per row" do
    sign_in @leader.user
    with_checklists { get applications_team_path(@juniors) }

    assert_select "form#intake-bulk-#{@juniors.id}"
    assert_select "input[type=checkbox][name='application_ids[]'][form='intake-bulk-#{@juniors.id}'][value='#{@application.id}']"
  end

  test "finishing the checklist tells the applicant a manager will decide" do
    refresh
    attest(@applicant)

    bodies = with_checklists { queued_email_bodies { refresh } }

    assert_equal 1, bodies.size
    assert_match "Everything for joining Juniors is done", bodies.first
  end

  test "the approval email lists what's still to do" do
    bodies = with_checklists do
      queued_email_bodies do
        @application.intake_approver = @leader.user
        @application.approve!
      end
    end

    assert_match "You're in: Juniors.", bodies.first
    assert_match "Next: Team agreement.", bodies.first
  end

  test "a registration's checklist is one its editor runs, and a gate needs one" do
    other = Checklist.create!(title: "Other team's", team: @mentors, status: :active, created_by: @admin)
    sign_in @juniors_leader.user
    registration = Intake::Registration.create!(team: @juniors, title: "Join Juniors", opens_at: 1.day.ago, apply_team_ids: [ @juniors.id ])

    with_checklists { patch intake_registration_path(registration), params: { intake_registration: { checklist_id: other.id } } }
    assert_nil registration.reload.checklist_id

    with_checklists { patch intake_registration_path(registration), params: { intake_registration: { gate_approval: "1", checklist_id: "" } } }
    assert_response :unprocessable_content
    assert_not registration.reload.gate_approval?
  end

  test "a manager points a registration to a checklist they run" do
    @registration.update!(checklist: nil)
    sign_in @leader.user
    with_checklists do
      get edit_intake_registration_path(@registration)
      assert_select "select[name='intake_registration[checklist_id]'] option[value='#{@checklist.id}']", "Joining"

      patch intake_registration_path(@registration), params: { intake_registration: { checklist_id: @checklist.id, gate_approval: "1" } }
    end

    assert_equal @checklist, @registration.reload.checklist
    assert @registration.gate_approval?
  end

  test "the registration page names the checklist and the teams whose applicants it misses" do
    sign_in @leader.user
    with_checklists { get intake_registration_path(@registration) }

    assert_match "Joining", response.body
    assert_match "It doesn't cover people applying to Mentors and Volunteers.", response.body
  end

  test "a checklist a registration uses can't be deleted" do
    assert_not @checklist.destroy
    assert_match "registrations", @checklist.errors.full_messages.to_sentence.downcase
  end

  test "the time kiosk lists items chosen for it that aren't done, for the person who scanned" do
    @agreement.update!(show_on_kiosk: true)
    Membership.create!(person: @applicant, team: @juniors)
    refresh
    token = Token.create!(tokenable: @applicant, value: "scan-#{SecureRandom.hex(4)}")
    sign_in @admin.user

    with_checklists { get time_kiosk_path, params: { time_kiosk: { tool: "find_token", token_value: token.value } } }

    assert_response :success
    assert_select "#kiosk-still-need li", count: 1, text: "Team agreement"
  end

  test "the time kiosk lists nothing for items not chosen for it" do
    Membership.create!(person: @applicant, team: @juniors)
    refresh
    token = Token.create!(tokenable: @applicant, value: "scan-#{SecureRandom.hex(4)}")
    sign_in @admin.user

    with_checklists { get time_kiosk_path, params: { time_kiosk: { tool: "find_token", token_value: token.value } } }

    assert_response :success
    assert_select "#kiosk-still-need", count: 0
  end

  test "an organizer chooses whether an item shows at the kiosk" do
    sign_in @leader.user
    with_checklists do
      patch checklist_checklist_item_path(@checklist, @agreement), params: { confirmed: "1", checklist_item: { label: "Team agreement",
        show_on_kiosk: "1", config: { statement: "Agreement signed", attested_by: "guardian" } } }
    end

    assert @agreement.reload.show_on_kiosk?
  end
end
