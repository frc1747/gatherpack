require "test_helper"
require_relative "../support/checklists_world"

class ChecklistFormItemTest < ActiveSupport::TestCase
  include ChecklistsWorld

  setup do
    @restore_settings = SettingsTestHelper.apply(feature_forms: "true")
    travel_to Time.zone.local(2026, 10, 1, 10)
    build_checklists_world
    @checklist = create_world_checklist
    add_rule(@checklist, :include, :team, team_id: @members.id)
    @form = create_form("Medical Release")
    @item = add_item(@checklist, :form_complete, "Medical", { form_ids: [ @form.id ] })
  end

  teardown do
    @restore_settings&.call
  end

  def create_form(title, include: [ @members ], status: :open, **attributes)
    form = Form.create!(title: title, team: @club, respond_permission: "family", read_permission: "family", status: :draft, **attributes)
    include.each { |team| form.form_audience_rules.create!(effect: :include, target_type: :team, team: team) }
    form.update!(status: status)
    form
  end

  def add_guardian_signature(form)
    form.form_questions.create!(kind: :signature, label: "Consent", signer: "guardian_if_minor")
  end

  # Fills in and submits a new version for the person, as themselves.
  def respond(form, name, as: name)
    subject = person(name)
    response = form.form_responses.find_or_create_by!(subject: subject)
    submission = response.start_submission!(person(as))
    submission.save!
    response.sync_status!
    errors = submission.submit!(person(as), FormAccess.new(person(as), subject, form))
    raise "submit errors: #{errors}" if errors.any?

    submission.reload
  end

  def sign(form, name, as:)
    submission = form.response_for(person(name)).open_submission
    signer = person(as)
    error = submission.sign!(form.signature_questions.first, signer: signer, typed_name: "#{signer.first_name} #{signer.last_name}",
      access: FormAccess.new(signer, person(name), form))
    raise "sign error: #{error}" if error
  end

  def result(name, item = @item)
    evaluate(@checklist, name, item)
  end

  test "done when the response is complete and was made within the item's dates" do
    respond(@form, :member)

    assert_equal "met", result(:member).status
    assert_equal "Completed October 01, 2026", result(:member).summary
    assert_equal "not_met", result(:member2).status
    assert_equal "No response yet", result(:member2).detail
    assert_equal "Fill it in", result(:member2).fix["label"]
    assert_equal "/forms/#{@form.to_param}/responses/#{person(:member2).to_param}/edit", result(:member2).fix["path"]
  end

  test "an older response, made before the item's dates, needs doing again unless any time counts" do
    travel_to(Time.zone.local(2026, 5, 1)) { respond(@form, :member) }

    assert_equal "not_met", result(:member).status
    assert_equal "Completed May 01, 2026, before September 01, 2026", result(:member).detail
    assert_equal "Do it again", result(:member).fix["label"]

    @item.update!(starts_on: Date.new(2026, 4, 1))
    assert_equal "met", result(:member).status, "the item's own dates override the checklist's"

    @item.update!(starts_on: nil, config: @item.config.merge("ever" => true))
    assert_equal "met", result(:member).status
  end

  test "a relative window: within the last N months moves with the date" do
    @item.update!(starts_within_amount: 6, starts_within_unit: "months")
    travel_to(Time.zone.local(2026, 5, 1)) { respond(@form, :member) }

    assert_equal "met", result(:member).status, "May is within the last 6 months of October"
    assert_equal Time.zone.local(2026, 10, 2), Checklists::Evaluator.new(@checklist.reload).next_change_at

    travel_to Time.zone.local(2026, 11, 2, 9)
    assert_equal "not_met", result(:member).status, "May 1 is more than 6 months before November 2"
    assert_match "before May 02, 2026", result(:member).detail
  end

  test "a form's expiry: Good until while it counts, Expired once it passes" do
    @form.update!(valid_for_months: 6)
    respond(@form, :member)

    assert_equal "met", result(:member).status
    assert_equal "Completed October 01, 2026. Good until April 01, 2027", result(:member).detail
    assert_equal Time.zone.local(2027, 4, 1, 10), Checklists::Kinds::FormComplete.next_change_at(@item.reload, Checklists::Context.new(@checklist.reload))

    travel_to Time.zone.local(2027, 4, 1, 11)
    assert_equal "not_met", result(:member).status, "expired before the expiry job stores it"
    assert_equal "Expired April 01, 2027", result(:member).summary
    assert_equal "Confirm it again", result(:member).fix["label"]

    @item.update!(config: @item.config.merge("ever" => true))
    assert_equal "not_met", result(:member).status, "an expired response isn't done whatever the dates say"
  end

  test "after the cutoff, signing again or expiring later doesn't change the result" do
    @checklist.update!(cutoff_on: Date.new(2026, 10, 15))
    @form.update!(expires_on: Date.new(2026, 10, 20))
    respond(@form, :member)
    travel_to(Time.zone.local(2026, 10, 10)) { respond(@form, :member2) && @form.response_for(person(:member2)).active_submission.withdraw!(by: person(:member2)) }

    travel_to Time.zone.local(2026, 10, 25, 9)
    assert_equal "met", result(:member).status, "the form expired after the cutoff"
    assert_equal "Completed October 01, 2026. Good until October 19, 2026", result(:member).detail
    assert_nil Checklists::Kinds::FormComplete.next_change_at(@item.reload, Checklists::Context.new(@checklist.reload)), "nothing moves with the clock after the cutoff"

    @form.update!(expires_on: nil)
    travel_to(Time.zone.local(2026, 11, 1)) { respond(@form, :member) }
    travel_to Time.zone.local(2026, 11, 2)
    assert_equal "met", result(:member).status, "signed again after the cutoff: the version that counted then still counts"
    assert_equal "Completed October 01, 2026", result(:member).summary

    @form.response_for(person(:member)).start_submission!(person(:member))
    assert_equal "met", result(:member).status, "a draft started after the cutoff is ignored"
    assert_equal "Withdrawn", result(:member2).summary, "withdrawn before the cutoff"

    travel_to(Time.zone.local(2026, 11, 3)) { respond(@form, :rookie) }
    assert_equal "not_met", result(:rookie).status
    assert_equal "Completed November 03, 2026, after October 15, 2026", result(:rookie).detail
  end

  test "a version withdrawn after the cutoff counted at the cutoff" do
    @checklist.update!(cutoff_on: Date.new(2026, 10, 15))
    respond(@form, :member)
    travel_to Time.zone.local(2026, 10, 20)
    @form.response_for(person(:member)).active_submission.withdraw!(by: person(:member))
    assert_equal "met", result(:member).status
  end

  test "a form's fixed expiry date is the next change while anyone has a complete response" do
    @form.update!(expires_on: Date.new(2027, 3, 1))
    context = Checklists::Context.new(@checklist.reload)
    assert_nil Checklists::Kinds::FormComplete.next_change_at(@item.reload, context), "nobody has a complete response yet"

    respond(@form, :member)
    assert_equal Time.zone.local(2027, 3, 1), Checklists::Kinds::FormComplete.next_change_at(@item, context)
    assert_equal "Completed October 01, 2026. Good until February 28, 2027", result(:member).detail
  end

  test "an open newer version is almost, and a guardian's signature awaited names the guardian" do
    add_guardian_signature(@form)
    travel_to(Time.zone.local(2026, 5, 1)) do
      respond(@form, :kid, as: :parent)
      sign(@form, :kid, as: :parent)
    end
    assert_equal "not_met", result(:kid).status, "signed before the dates"

    @form.response_for(person(:kid)).start_submission!(person(:parent))
    assert_equal "pending", result(:kid).status
    assert_equal "Started", result(:kid).summary
    assert_equal "Finish it", result(:kid).fix["label"]

    @form.response_for(person(:kid)).open_submission.submit!(person(:parent), FormAccess.new(person(:parent), person(:kid), @form))
    assert_equal "pending", result(:kid).status
    assert_equal "Waiting for #{person(:parent).identifier_name}'s signature", result(:kid).summary
    assert_equal "Sign it", result(:kid).fix["label"]

    sign(@form, :kid, as: :parent)
    assert_equal "met", result(:kid).status
  end

  test "a guardian's signature for someone with no guardian linked is not yet, with a fix to add one" do
    add_guardian_signature(@form)
    person(:rookie).update!(birthday: Date.new(2013, 1, 1))
    respond(@form, :rookie)

    assert_equal "not_met", result(:rookie).status, "nothing is in motion"
    assert_equal "Needs a guardian linked", result(:rookie).summary
    assert_equal "Add a guardian", result(:rookie).fix["label"]
    assert_equal "/people/#{person(:rookie).to_param}/relationships", result(:rookie).fix["path"]

    respond(@form, :kid, as: :parent)
    assert_equal "pending", result(:kid).status, "the kid has a guardian"
    assert_equal "Needs a guardian linked", result(:member).summary, "no birthday on file needs a guardian too, as forms decide"

    person(:member).update!(birthday: Date.new(1990, 1, 1))
    assert_equal "No response yet", result(:member).detail, "of age signs for themselves"
  end

  test "entering a birthday marks the person, since it decides who needs a guardian" do
    with_settings(feature_checklists: "true", feature_forms: "true") do
      refresh(@checklist)
      ChecklistRefresh.delete_all
      person(:rookie).update!(birthday: Date.new(2013, 1, 1))
      assert ChecklistRefresh.exists?(checklist: @checklist, person_id: person(:rookie).id)
    end
  end

  test "someone the form doesn't ask is not yet, never exempt, and listed as a problem" do
    @form.form_audience_rules.create!(effect: :exclude, target_type: :person, person: person(:member2))

    assert_equal "not_met", result(:member2).status
    assert_equal "This form isn't asking them; add them to its audience", result(:member2).detail
    assert_equal "/forms/#{@form.to_param}/edit?tab=audience", result(:member2).fix["path"]
    assert_includes @checklist.reload.problems, "Medical: 1 person covered here isn't asked Medical Release; add the checklist to its audience"
  end

  test "with forms turned off the item is not yet for everyone, and says why" do
    respond(@form, :member)
    with_settings(feature_forms: "false") do
      assert_equal "not_met", result(:member).status
      assert_equal "Forms are turned off", result(:member).detail
      assert_includes @checklist.reload.problems, "Medical: Forms are turned off, so this counts as not yet for everyone"
    end
  end

  test "closed, draft and closing forms and deleted forms are problems" do
    assert_empty @checklist.reload.problems

    @form.update!(closes_at: Time.zone.local(2027, 1, 15, 17))
    assert_includes @checklist.reload.problems, "Medical: Medical Release closes January 15, 2027"

    @form.update!(status: :closed)
    assert_includes @checklist.reload.problems, "Medical: Medical Release is closed; nobody can sign it"

    draft = create_form("Code of Conduct", status: :draft)
    add_item(@checklist, :form_complete, "Conduct", { form_ids: [ draft.id ] })
    assert_includes @checklist.reload.problems, "Conduct: Code of Conduct is a draft; nobody can sign it"

    assert_not draft.destroy, "the item protects the form"
    @item.update_columns(config: { "form_ids" => [ SecureRandom.uuid ] })
    assert_includes @checklist.reload.problems.join, "was deleted"
    assert_equal "not_met", result(:member).status
  end

  test "all of several forms: the first not done decides" do
    other = create_form("Code of Conduct")
    @item.update!(config: { "form_ids" => [ @form.id, other.id ] })
    respond(@form, :member)

    assert_equal "not_met", result(:member).status
    assert_equal "1 of 2 forms done", result(:member).summary
    assert_match "Code of Conduct: No response yet", result(:member).detail

    respond(other, :member)
    assert_equal "met", result(:member).status
  end

  test "a batch gives the same answers as one person at a time" do
    add_guardian_signature(@form)
    respond(@form, :kid, as: :parent)
    sign(@form, :kid, as: :parent)
    travel_to(Time.zone.local(2026, 5, 1)) do
      respond(@form, :member)
    end
    respond(@form, :member2)
    names = %i[member member2 kid rookie]

    batch = Checklists::Evaluator.new(@checklist.reload).call(names.map { |name| person(name).id })
    names.each do |name|
      single = result(name)
      assert_equal single.status, batch.dig(person(name).id, @item.id).status, name.to_s
      assert_equal single.summary, batch.dig(person(name).id, @item.id).summary, name.to_s
    end
  end

  test "stored results refresh when a response stops being complete" do
    respond(@form, :member)
    with_settings(feature_checklists: "true", feature_forms: "true") do
      refresh(@checklist)
      assert_equal "met", stored_status(@checklist, :member, @item)
      ChecklistRefresh.delete_all

      @form.response_for(person(:member)).active_submission.withdraw!(by: person(:member))

      assert_equal [ person(:member).id ], ChecklistRefresh.where(checklist: @checklist).pluck(:person_id)
      assert ChecklistResult.find_by(checklist: @checklist, item: @item, person: person(:member)).stale?
      refresh(@checklist)
      assert_equal "not_met", stored_status(@checklist, :member, @item)
    end
  end

  test "the expiry job's form_responses - incomplete marks the person, and the clock refreshes at the expiry" do
    @form.update!(valid_for_months: 1)
    respond(@form, :member)
    with_settings(feature_checklists: "true", feature_forms: "true") do
      refresh(@checklist)
      assert_equal Time.zone.local(2026, 11, 1, 10), @checklist.reload.next_refresh_at

      travel_to Time.zone.local(2026, 11, 1, 11)
      ChecklistRefresh.delete_all
      FormExpiryJob.perform_now

      assert_equal "needs_reconfirmation", FormResponse.find_by(form: @form, subject: person(:member)).read_attribute(:status)
      assert_equal [ person(:member).id ], ChecklistRefresh.where(checklist: @checklist).pluck(:person_id)
      refresh(@checklist)
      assert_equal "not_met", stored_status(@checklist, :member, @item)
    end
  end
end
