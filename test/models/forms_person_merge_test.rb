require "test_helper"
require_relative "../support/forms_world"

# Runs only where people can be merged (feature/person-merge is present).
class FormsPersonMergeTest < ActiveSupport::TestCase
  include FormsWorld

  COLUMNS = %w[
    forms.created_by_id form_responses.subject_id form_submissions.created_by_id form_submissions.submitted_by_id
    form_signatures.signer_id form_signatures.revoked_by_id form_audience_rules.person_id form_reminders.sent_by_id
  ].freeze

  setup do
    skip "people can't be merged here" unless defined?(GatherPack::PersonMerge)
  end

  test "every column forms adds is covered by a merge" do
    uncovered = COLUMNS.reject { |name| GatherPack::PersonMerge.covers?(*name.split(".")) }

    assert_empty uncovered
  end

  test "the more complete response stays, with its versions" do
    build_person_fields_world
    form = create_world_form
    add_choice(form, "Sandwich", [ "Slim 1", "Slim 4" ])
    respond(form, :a1, as: :a1, answers: { "sandwich" => "Slim 1" }, submit: false)
    submitted = respond(form, :a2, as: :a2, answers: { "sandwich" => "Slim 4" })

    merge(keep: person(:a1), drop: person(:a2))

    response = FormResponse.find_by!(form: form, subject: person(:a1))
    assert response.complete?
    assert_equal submitted, response.active_submission
    assert_equal [ submitted ], response.form_submissions.to_a
    assert_equal 1, form.form_responses.count
  end

  test "the kept person's response stays when both are as complete" do
    build_person_fields_world
    form = create_world_form
    add_choice(form, "Sandwich", [ "Slim 1", "Slim 4" ])
    kept = respond(form, :a1, as: :a1, answers: { "sandwich" => "Slim 1" })
    respond(form, :a2, as: :a2, answers: { "sandwich" => "Slim 4" })

    merge(keep: person(:a1), drop: person(:a2))

    response = FormResponse.find_by!(form: form, subject: person(:a1))
    assert_equal kept, response.active_submission
    assert_equal 1, FormSubmission.where(form_response: form.form_responses).count
  end

  private

  def merge(keep:, drop:)
    admin = User.create!(email: "forms-merge-admin@example.com", password: "Password1!", admin: true)
    assert PersonMerger.new(keep_nid: keep.neat_id, drop_nid: drop.neat_id, keep_login: "keep").merge(actor: admin)
  end
end
