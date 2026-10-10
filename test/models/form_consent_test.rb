require "test_helper"
require_relative "../support/forms_world"
require_relative "../support/settings_test_helper"

class FormConsentTest < ActiveSupport::TestCase
  include FormsWorld
  include SettingsTestHelper

  setup do
    build_person_fields_world
    @badge = create_world_badge("Consent Signed")
    @form = create_world_form("Parent Consent", completion_badge: @badge)
    @photo = add_choice(@form, "Photo release", %w[ Yes No ], required: true)
    @consent = add_signature(@form, "Parent consent", signer: "guardian_if_minor")
  end

  def holds_badge?(name)
    BadgeAssignment.exists?(badge: @badge, person: person(name))
  end

  test "a guardian's signature completes a minor's response and grants the badge" do
    submission = respond(@form, :a1, as: :a1, answers: { "photo_release" => "Yes" })
    assert submission.pending?
    assert submission.form_response.reload.waiting?
    assert_equal [ @consent ], submission.missing_signatures
    assert_not holds_badge?(:a1)

    a1 = FormAccess.new(person(:a1), person(:a1), @form)
    assert_not a1.can_sign?(@consent), "A1 has a guardian, so A1 doesn't sign"
    assert_equal "You can't sign this.", submission.sign!(@consent, signer: person(:a1), typed_name: "A1 World", access: a1)

    signed = sign(@form, :a1, as: :parent_a1)
    assert signed.active?
    assert signed.form_response.reload.complete?
    assert holds_badge?(:a1)
    signature = signed.form_signatures.first
    assert signature.signed_as_guardian?
    assert signature.matches?(signed)
    assert_equal signed.content_digest, signature.content_digest
    assert_equal "Photo release", signed.content["questions"].detect { |question| question["key"] == "photo_release" }["label"]
  end

  test "the typed name must match the signer's name" do
    submission = respond(@form, :a1, as: :parent_a1, answers: { "photo_release" => "Yes" })
    access = FormAccess.new(person(:parent_a1), person(:a1), @form)
    error = submission.sign!(@consent, signer: person(:parent_a1), typed_name: "Someone Else", access: access)
    assert_match "Type your full name", error
    assert_nil submission.sign!(@consent, signer: person(:parent_a1), typed_name: "  parenta1   WORLD ", access: access)
  end

  test "guardian_if_minor goes by age when the birthday is known" do
    respond(@form, :a1, as: :a1, answers: { "photo_release" => "Yes" })
    a1 = FormAccess.new(person(:a1), person(:a1), @form)
    parent = FormAccess.new(person(:parent_a1), person(:a1), @form)

    person(:a1).update!(birthday: 17.years.ago.to_date)
    assert_not a1.can_sign?(@consent), "a minor doesn't sign for themselves"
    assert parent.can_sign?(@consent)

    person(:a1).update!(birthday: 18.years.ago.to_date)
    assert_equal :subject, FormAccess.new(person(:a1), person(:a1), @form).signing_role(@consent), "of age, even with a guardian linked"
    assert_equal :guardian, FormAccess.new(person(:parent_a1), person(:a1), @form).signing_role(@consent), "a guardian still may"

    with_settings(guardianship_age_limit: "21") do
      assert_not FormAccess.new(person(:a1), person(:a1), @form).can_sign?(@consent), "the guardianship age limit sets the age"
    end

    person(:b1).update!(birthday: 15.years.ago.to_date)
    assert_not FormAccess.new(person(:b1), person(:b1), @form).can_sign?(@consent), "a minor with no guardian linked waits for one"
    assert sign(@form, :a1, as: :a1).active?
  end

  test "with no birthday on file, only a guardian signs, so someone with none linked waits" do
    submission = respond(@form, :b1, as: :b1, answers: { "photo_release" => "No" })
    assert_not FormAccess.new(person(:b1), person(:b1), @form).can_sign?(@consent)
    assert submission.pending?

    person(:b1).update!(birthday: 19.years.ago.to_date)
    assert sign(@form, :b1, as: :b1).active?, "once the birthday shows they're of age, they sign"
  end

  test "a leader can record a paper signature only where the question allows it" do
    paper = create_world_form("Paper Slip")
    add_signature(paper, "Signed slip", signer: "leader")
    respond(paper, :a1, as: :den_a_leader, answers: {})
    assert_not FormAccess.new(person(:parent_a1), person(:a1), paper).can_sign?(paper.signature_questions.first)
    signed = sign(paper, :a1, as: :den_a_leader)
    assert signed.active?
    assert signed.form_signatures.first.signed_as_leader?
  end

  test "changing a pending submission's answers revokes its signatures" do
    student = add_signature(@form, "Student agreement", signer: "subject")
    submission = respond(@form, :a1, as: :a1, answers: { "photo_release" => "Yes" })
    sign(@form, :a1, as: :a1, question: student)
    assert submission.reload.pending?, "still waiting for the parent"

    submission.assign_answers({ "photo_release" => "No" }, FormAccess.new(person(:a1), person(:a1), @form))
    submission.save!
    assert submission.draft?
    revoked = submission.form_signatures.reload.first
    assert_equal "Answers changed after signing", revoked.revoked_reason
    assert_empty submission.standing_signatures
  end

  test "an update needs fresh signatures, and the signed version stays in effect meanwhile" do
    respond(@form, :a1, as: :a1, answers: { "photo_release" => "Yes" })
    first = sign(@form, :a1, as: :parent_a1)
    response = first.form_response.reload

    update = respond(@form, :a1, as: :a1, answers: { "photo_release" => "No" })
    assert update.pending?
    assert_empty update.form_signatures
    assert_equal first, response.reload.active_submission
    assert response.complete?
    assert holds_badge?(:a1)
  end

  test "withdrawing revokes the signatures and removes the badge" do
    respond(@form, :a1, as: :a1, answers: { "photo_release" => "Yes" })
    signed = sign(@form, :a1, as: :parent_a1)
    signed.withdraw!(by: person(:parent_a1))
    assert signed.form_response.reload.withdrawn?
    assert_not holds_badge?(:a1)
    assert_equal "Withdrawn", signed.form_signatures.reload.first.revoked_reason
  end

  test "changing an answered form starts a new version; publishing can ask for re-confirmation" do
    respond(@form, :a1, as: :a1, answers: { "photo_release" => "Yes" })
    complete = sign(@form, :a1, as: :parent_a1)
    waiting = respond(@form, :a2, as: :parent_a2, answers: { "photo_release" => "No" })
    assert waiting.pending?

    @consent.update!(body: "I give permission, including overnight trips.")
    @form.reload
    assert_equal 2, @form.content_version
    assert @form.unpublished_changes?
    assert waiting.reload.draft?, "waiting submissions go back to draft"
    assert_equal 2, waiting.form_version

    @photo.update!(label: "Photo release (website)")
    @form.reload.update!(description: "Read this first.")
    assert_equal 2, @form.reload.content_version, "one version until published"

    @form.publish!(reconfirm: false)
    assert complete.form_response.reload.complete?

    @form.update!(description: "Read this first, carefully.")
    assert_equal 3, @form.reload.content_version, "the description is content too"
    @form.publish!(reconfirm: true)
    response = complete.form_response.reload
    assert response.needs_reconfirmation?
    assert_equal :form, response.reconfirmation_reason
    assert_equal complete, response.active_submission, "the signed answers stay in effect"
    assert_not holds_badge?(:a1)
    assert FormAccess.new(person(:a1), person(:a1), @form.tap { |form| form.update!(allow_updates: false) }).can_update?,
      "a response needing re-confirmation can be updated even without allow updates"

    respond(@form, :a1, as: :a1, answers: { "photo_release" => "Yes" })
    sign(@form, :a1, as: :parent_a1)
    assert response.reload.complete?
    assert holds_badge?(:a1)
  end

  test "a profile change sends a response back for re-confirmation when the form asks for it" do
    with_settings(feature_person_fields: "true") do
      contact = create_world_field("Emergency Contact", read: "family", write: "family")
      add_profile_question(@form, contact, :update_profile)
      @form.update!(reconfirm_on_profile_change: true)

      respond(@form, :a1, as: :a1, answers: { "photo_release" => "Yes", "emergency_contact" => "Grandma" })
      signed = sign(@form, :a1, as: :parent_a1)
      assert_equal "Grandma", person(:a1).reload.field_value(contact)
      response = signed.form_response.reload
      assert response.complete?, "writing the profile on activation doesn't count as a change"
      assert holds_badge?(:a1)

      a1 = Person.find(person(:a1).id)
      a1.assign_field_values({ "emergency_contact" => "Uncle Bob" }, acting: person(:den_a_leader))
      a1.save!
      response.reload
      assert response.needs_reconfirmation?
      assert_equal :profile, response.reconfirmation_reason
      assert_equal [ "Emergency Contact" ], response.profile_changes.map(&:label)
      assert_not holds_badge?(:a1)
    end
  end

  test "without the setting a profile change is only flagged" do
    with_settings(feature_person_fields: "true") do
      contact = create_world_field("Emergency Contact", read: "family", write: "family")
      add_profile_question(@form, contact, :update_profile)
      respond(@form, :a1, as: :a1, answers: { "photo_release" => "Yes", "emergency_contact" => "Grandma" })
      response = sign(@form, :a1, as: :parent_a1).form_response

      a1 = Person.find(person(:a1).id)
      a1.assign_field_values({ "emergency_contact" => "Uncle Bob" }, acting: person(:den_a_leader))
      a1.save!
      assert response.reload.complete?
      assert_equal [ "Emergency Contact" ], response.profile_changes.map(&:label)
      assert FormReport.new(@form, viewer: person(:den_a_leader)).then { |report| report.changed_since_signed?(report.rows.detect { |row| row.person == person(:a1) }, "emergency_contact") }
    end
  end

  test "a team completion badge must cover everyone asked" do
    den_badge = create_world_badge("Den A Consent", team: @den_a)
    @form.completion_badge = den_badge
    assert_not @form.valid?, "the form asks all of Pack"
    assert @form.errors.key?(:completion_badge)

    den_form = create_world_form("Den A Consent", include: [ @den_a ], completion_badge: den_badge)
    rule = den_form.form_audience_rules.build(effect: :include, target_type: :person, person: person(:b1))
    assert_not rule.valid?
  end

  test "a guardian signature needs a read level guardians reach" do
    form = create_world_form("Student Only", respond: "self_and_leaders", read: "self_and_leaders")
    question = form.form_questions.build(kind: :signature, label: "Parent", signer: "guardian")
    assert_not question.valid?
    assert question.errors.key?(:signer)
  end
end
