require "test_helper"
require_relative "../support/forms_world"
require_relative "../support/settings_test_helper"

class FormConsentFlowTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers
  include FormsWorld
  include SettingsTestHelper

  setup do
    host! "localhost"
    build_person_fields_world
    @badge = create_world_badge("Consent Signed")
    @form = create_world_form("Parent Consent", completion_badge: @badge)
    add_choice(@form, "Photo release", %w[ Yes No ], required: true)
    @form.form_questions.create!(kind: :acknowledgment, label: "I have read the code of conduct", required: true, write_permission: "self")
    @consent = add_signature(@form, "Parent consent", body: "I give permission.")
    person(:b1).update!(birthday: 19.years.ago.to_date) # of age, so B1 signs for themselves
  end

  test "the student submits, the parent signs, and the badge is granted" do
    with_feature do
      as(:a1) do
        get edit_form_response_path(@form, person(:a1))
        assert_response :success
        assert_select "div", text: /Signed after submitting, by a guardian/

        patch form_response_path(@form, person(:a1)), params: { submit: "1", form_response: { answers: { photo_release: "Yes", i_have_read_the_code_of_conduct: "0" } } }
        assert_response :unprocessable_entity, "the acknowledgment must be ticked"
        assert_match "must be ticked", response.body

        patch form_response_path(@form, person(:a1)), params: { submit: "1", form_response: { answers: { photo_release: "Yes", i_have_read_the_code_of_conduct: "1" } } }
        assert_redirected_to form_response_path(@form, person(:a1))
        follow_redirect!
        assert_match "waiting for a guardian", response.body
        assert_select "form[action=?]", sign_form_response_path(@form, person(:a1)), count: 0
      end

      as(:parent_a1) do
        get forms_path
        assert_select "a[href=?]", edit_form_response_path(@form, person(:a1)), count: 0
        assert_select "a[href=?]", form_response_path(@form, person(:a1))

        get form_response_path(@form, person(:a1))
        assert_select "form[action=?]", sign_form_response_path(@form, person(:a1))

        post sign_form_response_path(@form, person(:a1)), params: { question_id: @consent.id, typed_name: "Wrong Name" }
        assert_match "Type your full name", flash[:alert]

        post sign_form_response_path(@form, person(:a1)), params: { question_id: @consent.id, typed_name: "ParentA1 World" }
        assert_match "complete", flash[:notice]
      end
    end

    assert @form.response_for(person(:a1)).complete?
    assert BadgeAssignment.exists?(badge: @badge, person: person(:a1))
    submission = @form.response_for(person(:a1)).active_submission
    assert_equal "127.0.0.1", submission.form_signatures.first.ip_address

    with_feature do
      as(:den_a_leader) do
        get form_response_submission_path(@form, person(:a1), submission)
        assert_response :success
        assert_select "td", text: "ParentA1 World"
        assert_select "div", text: /I give permission/

        get results_form_path(@form)
        assert_select "td", text: /ParentA1 World/
      end
    end
  end

  test "a student sees parent-only items greyed out, without a to-do or a Submit button" do
    form = create_world_form("Travel")
    form.form_questions.create!(kind: :acknowledgment, label: "Dues are paid", body: "Examples include: checks", required: true, write_permission: "guardians")
    add_signature(form, "Parent", signer: "guardian")
    with_feature do
      as(:a1) do
        get edit_form_response_path(form, person(:a1))
        assert_response :success
        assert_select "input[type=checkbox][disabled]"
        assert_match "for a parent or guardian to fill in", response.body
        assert_select "input[type=submit][name=submit]", count: 0
        get forms_path
        assert_select "a[href=?]", edit_form_response_path(form, person(:a1)), count: 0
        get person_forms_path(person(:a1))
        assert_select "h2", text: "Waiting on someone else"
      end
      as(:parent_a1) do
        get edit_form_response_path(form, person(:a1))
        assert_select ".form-acknowledgment input[type=checkbox]:not([disabled])"
        assert_select ".form-acknowledgment-detail", text: /Examples include/
        patch form_response_path(form, person(:a1)), params: { submit: "1", form_response: { answers: { dues_are_paid: "0" } } }
        assert_select ".invalid-feedback", text: "must be ticked"
      end
    end
  end

  test "every edit tab renders, and badge settings disappear while Badges are off" do
    @form.form_badge_grants.create!(badge: @health_officer_badge, access: :read)
    with_feature do
      as(:admin) do
        %w[ details questions audience permissions responses ].each do |tab|
          get edit_form_path(@form, tab: tab)
          assert_response :success, tab
          assert_select "a.nav-link.active[href=?]", edit_form_path(@form, tab: tab)
        end
        get edit_form_path(@form, tab: "responses")
        assert_select "select[name=?]", "form[completion_badge_id]"
        get edit_form_path(@form, tab: "permissions")
        assert_select "h2", text: "Access through badges"
      end

      with_settings(feature_badges: "false") do
        as(:admin) do
          get edit_form_path(@form, tab: "responses")
          assert_select "select[name=?]", "form[completion_badge_id]", count: 0
          assert_match "Badges are turned off", response.body
          get edit_form_path(@form, tab: "permissions")
          assert_select "h2", text: "Access through badges", count: 0
          get edit_form_path(@form, tab: "audience")
          assert_select "input[type=submit][value=?]", "Add badge", count: 0
          assert_select "select[name=?]", "form[audience_badge_id]", count: 0

          patch form_path(@form), params: { tab: "responses", form: { completion_badge_id: "" } }
          assert_equal @badge, @form.reload.completion_badge, "badge settings don't change while Badges are off"
        end
        respond(@form, :b1, as: :b1, answers: { "photo_release" => "Yes", "i_have_read_the_code_of_conduct" => true })
        sign(@form, :b1, as: :b1)
        assert @form.response_for(person(:b1)).complete?
        assert_not BadgeAssignment.exists?(badge: @badge, person: person(:b1)), "no badges handed out while Badges are off"
        assert_not FormAccess.new(person(:health_officer), person(:a1), @form).can_read?, "badge grants wait too"
      end
    end
  end

  test "the profile Forms tab shows the person's forms to them, guardians, and leaders" do
    with_feature do
      as(:parent_a1) do
        get person_forms_path(person(:a1))
        assert_response :success
        assert_select "h2", text: "To do"
        assert_select "a", text: "Fill in"
        assert_select "a[href=?]", edit_form_response_path(@form, person(:a1)), text: "Parent Consent"
      end
      as(:parent_a1) do
        get person_forms_path(person(:parent_a1))
        assert_response :success
        assert_select "h2", text: "For your children"
        assert_select "strong", text: "A1 World"
        assert_select "a[href=?]", edit_form_response_path(@form, person(:a1)), text: "Fill in"
      end
      as(:den_a_leader) do
        get person_path(person(:a1))
        assert_select "a[href=?]", person_forms_path(person(:a1))
      end
      as(:a2) do
        get person_path(person(:a1))
        assert_select "a[href=?]", person_forms_path(person(:a1)), count: 0
        get person_forms_path(person(:a1))
        assert_redirected_to person_path(person(:a1))
      end
    end
  end

  test "managers edit who is asked, see the list, and publish changes" do
    respond(@form, :b1, as: :b1, answers: { "photo_release" => "Yes", "i_have_read_the_code_of_conduct" => true })
    sign(@form, :b1, as: :b1)

    with_feature do
      as(:pack_leader) do
        get edit_form_path(@form, tab: "audience")
        assert_response :success
        assert_select "#audience li", text: /Include Pack/

        post form_audience_rules_path(@form), params: { form_audience_rule: { effect: "exclude", target_type: "team", team_id: @den_b.id } }
        assert_match "added", flash[:notice]
        get audience_form_path(@form)
        assert_select "li", text: "B1 World", count: 1
        assert_select "h2", text: /No longer asked/

        post form_audience_rules_path(@form), params: { form_audience_rule: { effect: "include", target_type: "team", team_id: @other_org.id } }
        assert_equal "You are not allowed to do that", flash[:notice]
        assert_not @form.form_audience_rules.exists?(team: @other_org)

        patch form_question_path(@form, @consent), params: { form_question: { body: "I give permission, overnight too." } }
        get edit_form_path(@form)
        assert_select "h2", text: /changed since people responded/

        post publish_form_path(@form, reconfirm: "1")
        assert_match "signed again", flash[:notice]
      end
    end
    assert @form.response_for(person(:b1)).reload.needs_reconfirmation?
  end

  test "managers can add acknowledgment and signature questions; only admins set badges" do
    with_feature do
      as(:pack_leader) do
        get new_form_question_path(@form, kind: "signature")
        assert_response :success
        get new_form_question_path(@form, kind: "acknowledgment")
        assert_response :success

        patch form_path(@form), params: { form: { completion_badge_id: "" } }
        assert_equal @badge, @form.reload.completion_badge, "non-admins can't change the completion badge"

        post form_badge_grants_path(@form), params: { form_badge_grant: { badge_id: @health_officer_badge.id, access: "read" } }
        assert_equal "You are not allowed to do that", flash[:notice]
        assert_empty @form.form_badge_grants
      end
      as(:admin) do
        post form_badge_grants_path(@form), params: { form_badge_grant: { badge_id: @health_officer_badge.id, access: "read" } }
        assert_equal [ @health_officer_badge ], @form.form_badge_grants.map(&:badge)
      end
    end
  end

  test "the status, tally, and preview pages show signatures and people no longer asked" do
    respond(@form, :a1, as: :a1, answers: { "photo_release" => "Yes", "i_have_read_the_code_of_conduct" => true })
    respond(@form, :b1, as: :b1, answers: { "photo_release" => "No", "i_have_read_the_code_of_conduct" => true })
    sign(@form, :b1, as: :b1)
    add_rule(@form, person(:b1), effect: :exclude)

    with_feature do
      as(:pack_leader) do
        get form_path(@form)
        assert_response :success
        assert_select "small", text: /Waiting for a guardian/
        assert_select "a", text: /No longer asked \(1\)/
        get tally_form_path(@form)
        assert_response :success
        get preview_form_path(@form, preview: { viewer_id: person(:parent_a1).id, subject_id: person(:a1).id })
        assert_select "td", text: /Can sign \(guardian\)/
      end
    end
  end

  private

  def with_feature(&block)
    with_settings(feature_forms: "true", &block)
  end

  def as(name)
    sign_in person(name).user
    yield
  ensure
    sign_out :user
  end
end
