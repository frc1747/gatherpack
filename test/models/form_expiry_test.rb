require "test_helper"
require_relative "../support/forms_world"
require_relative "../support/settings_test_helper"

class FormExpiryTest < ActiveSupport::TestCase
  include FormsWorld
  include SettingsTestHelper

  setup do
    travel_to Time.zone.local(2026, 6, 15, 10)
    build_person_fields_world
    @badge = create_world_badge("Physical on File")
    @form = create_world_form("Physical", completion_badge: @badge)
    add_choice(@form, "Cleared", %w[ Yes No ])
  end

  def response_for(name)
    @form.response_for(person(name)).reload
  end

  def holds_badge?(name)
    BadgeAssignment.exists?(badge: @badge, person: person(name))
  end

  def run_job
    with_settings(feature_forms: "true") { FormExpiryJob.perform_now }
  end

  test "responses never expire while both expiry fields are blank" do
    respond(@form, :a1, as: :a1, answers: { "cleared" => "Yes" })
    assert_not @form.expires?
    assert_equal "never", @form.expiry

    travel 10.years
    run_job

    response = response_for(:a1)
    assert response.complete?
    assert_nil response.expires_at
    assert_nil response.expiry_summary
    assert_nil response.reconfirmation_reason
    assert holds_badge?(:a1)
  end

  test "a date expires every response from the start of that day" do
    @form.update!(expires_on: Date.new(2027, 6, 1))
    respond(@form, :a1, as: :a1, answers: { "cleared" => "Yes" })
    response = response_for(:a1)
    assert response.complete?
    assert_equal Time.zone.local(2027, 6, 1), response.expires_at
    assert_equal "Good until May 31, 2027", response.expiry_summary

    travel_to Time.zone.local(2027, 5, 31, 23, 59)
    run_job
    assert response_for(:a1).complete?

    travel_to Time.zone.local(2027, 6, 1)
    response = response_for(:a1)
    assert response.expired?
    assert_equal :expired, response.reconfirmation_reason, "computed when read, before the job stores it"
    assert_equal "Expired June 1, 2027", response.expiry_summary

    run_job
    response = response_for(:a1)
    assert response.needs_reconfirmation?
    assert_not holds_badge?(:a1)
  end

  test "months after signing run from each response's activation" do
    @form.update!(valid_for_months: 12)
    signed = respond(@form, :a1, as: :a1, answers: { "cleared" => "Yes" })
    travel 2.months
    respond(@form, :b1, as: :b1, answers: { "cleared" => "Yes" })

    assert_equal signed.activated_at + 12.months, response_for(:a1).expires_at
    assert_equal "Good until June 15, 2027", response_for(:a1).expiry_summary

    travel_to signed.activated_at + 12.months
    run_job
    assert response_for(:a1).needs_reconfirmation?
    assert_equal :expired, response_for(:a1).reconfirmation_reason
    assert response_for(:b1).complete?, "B1's year started two months later"
  end

  test "signing again restarts the months" do
    @form.update!(valid_for_months: 12, allow_updates: false)
    respond(@form, :a1, as: :a1, answers: { "cleared" => "Yes" })
    travel 13.months
    run_job
    assert response_for(:a1).needs_reconfirmation?
    assert FormAccess.new(person(:a1), person(:a1), @form).can_update?, "an expired response can be updated even with updates off"

    again = respond(@form, :a1, as: :a1, answers: { "cleared" => "Yes" })
    response = response_for(:a1)
    assert response.complete?
    assert_equal again.activated_at + 12.months, response.expires_at
    assert holds_badge?(:a1)
  end

  test "the job marks an expired response once and runs the incomplete hook once" do
    events = []
    Hook.create!(name: "Incomplete", event: "form_responses - incomplete", code: "Thread.current[:form_expiry_events] << model.status")
    Thread.current[:form_expiry_events] = events
    @form.update!(valid_for_months: 1)
    respond(@form, :a1, as: :a1, answers: { "cleared" => "Yes" })

    travel 2.months
    run_job
    run_job

    assert_equal [ "needs_reconfirmation" ], events
    assert_empty FormResponse.past_expiry
  ensure
    Thread.current[:form_expiry_events] = nil
  end

  test "the job waits while forms are off" do
    @form.update!(valid_for_months: 1)
    respond(@form, :a1, as: :a1, answers: { "cleared" => "Yes" })
    travel 2.months

    FormExpiryJob.perform_now
    assert response_for(:a1).complete?
    assert holds_badge?(:a1)

    run_job
    assert response_for(:a1).needs_reconfirmation?
  end

  test "saving the expiry resyncs the form's responses" do
    respond(@form, :a1, as: :a1, answers: { "cleared" => "Yes" })

    @form.update!(expiry: "date", expires_on: Date.current)
    assert response_for(:a1).needs_reconfirmation?
    assert_not holds_badge?(:a1)

    @form.update!(expiry: "never")
    assert_nil @form.reload.expires_on
    assert response_for(:a1).complete?
    assert holds_badge?(:a1)
  end

  test "the expiry choice keeps one column and needs its value" do
    @form.update!(expiry: "date", expires_on: Date.new(2027, 6, 1), valid_for_months: 12)
    assert_equal [ Date.new(2027, 6, 1), nil ], [ @form.expires_on, @form.valid_for_months ]
    assert_equal "date", @form.expiry

    @form.update!(expiry: "months", expires_on: Date.new(2027, 6, 1), valid_for_months: 12)
    assert_equal [ nil, 12 ], [ @form.expires_on, @form.valid_for_months ]
    assert_equal "months", Form.find(@form.id).expiry

    assert_not @form.update(expiry: "date", expires_on: nil)
    assert @form.errors.key?(:expires_on)

    form = Form.find(@form.id)
    assert_not form.update(valid_for_months: 0)
    assert form.errors.key?(:valid_for_months)
    assert_not form.update(expires_on: Date.new(2027, 6, 1), valid_for_months: 12)
    assert form.errors.key?(:base), "at most one is set"
  end

  test "duplicating copies the expiry" do
    @form.update!(valid_for_months: 12)
    assert_equal 12, @form.duplicate!(title: "Physical 2027").valid_for_months
  end
end
