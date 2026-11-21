require "test_helper"
require_relative "../support/forms_world"
require_relative "../support/settings_test_helper"

# The form page is also its results, totals and printable list.
class FormResultsPageTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers
  include ActionMailer::TestHelper
  include ActiveJob::TestHelper
  include FormsWorld
  include SettingsTestHelper

  setup do
    host! "localhost"
    build_person_fields_world
    @form = create_world_form
    @sandwich = add_choice(@form, "Sandwich", [ "Slim 1", "Slim 4", "Big John" ])
    @note = @form.form_questions.create!(kind: :input, label: "Note", data_type: :string)
    respond(@form, :a1, as: :a1, answers: { "sandwich" => "Slim 4", "note" => "No onions" })
    respond(@form, :b1, as: :b1, answers: { "sandwich" => "Big John" })
  end

  test "answers and status are one table, and the filters narrow the table and the totals" do
    with_feature do
      as(:pack_leader) do
        get form_path(@form)
        assert_response :success
        assert_select "tr#person_#{person(:a1).id}" do
          assert_select "td a", text: "A1 World"
          assert_select "td .badge", text: "Complete"
          assert_select "td", text: /#1 · .* by A1 World/
          assert_select "td", text: "Slim 4"
          assert_select "td", text: "No onions"
        end
        assert_select "tr#person_#{person(:a2).id} td .badge", text: "Not started"
        assert_select "#totals tr", text: /Slim 4\s+1\b/
        assert_select "#totals tr", text: /Big John\s+1\b/
        assert_select "#totals h3", text: "Note", count: 0, msg: "only choice and yes/no questions are counted"

        get form_path(@form, status: "not_started")
        assert_select "tr#person_#{person(:a1).id}", count: 0
        assert_select "tr#person_#{person(:a2).id}"
        assert_select "#totals tr", text: /Slim 4\s+0\b/
        assert_select "#totals tr", text: /No answer\s+[1-9]/

        get form_path(@form, team_id: @den_a.id)
        assert_select "tr#person_#{person(:b1).id}", count: 0
        assert_select "tr#person_#{person(:a1).id}"
        assert_select "#totals tr", text: /Big John\s+0\b/
        assert_select "#totals tr", text: /Slim 4\s+1\b/
        assert_select "#status-filter a[href=?]", form_path(@form, team_id: @den_a.id, status: "complete"), text: "Complete (1)"
      end
    end
  end

  test "hide totals folds them away, also when printing" do
    with_feature do
      as(:pack_leader) do
        get form_path(@form)
        assert_select "#totals:not([hidden])"
        assert_select "a[href=?][data-action='form-results#toggleTotals']", form_path(@form, totals: "hidden"), text: "Hide totals"

        get form_path(@form, totals: "hidden", layout: "labels")
        assert_select "[data-controller=form-results][data-form-results-hidden-value=true]"
        # Hidden is display: none, on screen and on paper.
        assert_select "#totals[hidden]"
        assert_select "a[href=?]", form_path(@form, layout: "labels"), text: "Show totals"
        assert_select "#form-options input[type=hidden][name=totals][value=hidden]", msg: "Show keeps them hidden"
      end
    end
  end

  test "column tick boxes decide the table, the labels and the CSV alike" do
    with_settings(feature_forms: "true", feature_person_fields: "true") do
      allergies = create_world_field("Food Allergies", read: "family", write: "family")
      person(:a1).set_field_value(allergies, "peanut")

      as(:pack_leader) do
        get form_path(@form)
        assert_select "input[type=checkbox][name=?][value=?][checked]", "question_ids[]", @sandwich.id
        assert_select "input[type=checkbox][name=?][value=?][checked]", "question_ids[]", @note.id
        assert_select "input[type=checkbox][name=?][value=?]:not([checked])", "field_ids[]", allergies.id
        assert_select "details#more-choices:not([open])"

        columns = { columns_for: @form.id, question_ids: [ @note.id ], field_ids: [ allergies.id ] }
        get form_path(@form, columns)
        assert_select "details#more-choices[open]"
        assert_select "#responses th", text: "Note"
        assert_select "#responses th", text: "Food Allergies"
        assert_select "#responses th", text: "Sandwich", count: 0
        assert_select "#labels", text: /Note: No onions/
        assert_select "#labels", text: /Food Allergies: peanut/
        assert_select "#labels", text: /Sandwich/, count: 0
        assert_select "a[href=?]", form_path(@form, columns.merge(format: :csv)), text: "Download CSV"

        get form_path(@form, columns.merge(format: :csv))
        csv = CSV.parse(response.body)
        assert_equal [ "Note", "Food Allergies" ], csv.first.last(2)
        assert_not_includes csv.first, "Sandwich"
        assert_equal [ "No onions", "peanut" ], csv.detect { |row| row[1] == "A1" }.last(2)

        get form_path(@form, status: "complete", format: :csv)
        assert_equal [ "A1", "B1" ], CSV.parse(response.body).drop(1).map { |row| row[1] }.sort

        # The same options as the old results CSV give the same file.
        get form_path(@form, format: :csv, field_ids: [ allergies.id ])
        report = FormReport.new(@form, viewer: person(:pack_leader))
        assert_equal ApplicationController.helpers.form_results_csv(report, [ allergies ]), response.body
      end
    end
  end

  test "the old results, tally and printable list links land on the form page with their options" do
    with_feature do
      as(:pack_leader) do
        get results_form_path(@form, team_id: @den_a.id, version: "latest")
        assert_redirected_to form_path(@form, team_id: @den_a.id, version: "latest")
        get results_form_path(@form, format: :csv)
        assert_redirected_to form_path(@form, format: :csv)

        get tally_form_path(@form, who: "answered", question_id: @sandwich.id, answers: { @sandwich.id => [ "Slim 4" ] })
        assert_redirected_to form_path(@form, who: "answered", question_id: @sandwich.id, answers: { @sandwich.id => [ "Slim 4" ] })
        follow_redirect!
        assert_select "tr#person_#{person(:a1).id}"
        assert_select "tr#person_#{person(:b1).id}", count: 0

        get print_list_forms_path(form_id: @form.id, layout: "labels", columns_for: @form.id, question_ids: [ @note.id ])
        assert_redirected_to form_path(@form, layout: "labels", columns_for: @form.id, question_ids: [ @note.id ])

        get print_list_forms_path
        assert_response :success
        assert_select "select#form_id option", text: "Meal Choices"
      end
    end
  end

  test "people the form only shares totals with get totals, never answers" do
    @form.update!(totals_visibility: :audience)
    with_feature do
      as(:a2) do
        get tally_form_path(@form)
        assert_response :success
        assert_select "#totals h2", text: "Sandwich"
        assert_select "#totals tr", text: /Slim 4\s+1\b/
        assert_no_match "A1 World", response.body
        assert_no_match "No onions", response.body

        get form_path(@form)
        assert_redirected_to root_path

        get form_response_path(@form, person(:a2))
        assert_select "a[href=?]", tally_form_path(@form), text: "See totals"
      end
    end
  end

  test "the footer shows Edit and Remind, and More holds the rest" do
    with_feature do
      as(:pack_leader) do
        get form_path(@form)
        assert_select "#actions > .screen-action-row > a.btn.btn-warning", text: "Edit"
        assert_select "#actions > .screen-action-row > a.btn.btn-primary", text: /\ARemind \(\d+\)\z/
        assert_select "#actions > .screen-action-row > a, #actions > .screen-action-row > form", count: 2
        assert_select "#actions .dropdown-toggle.btn-secondary", text: "More"
        assert_select "#actions .dropdown-menu li:not(.d-md-none)", count: 3
        %w[ Results Tally Open Close ].each { |word| assert_select "a, button", text: word, count: 0 }
        assert_select "a", text: "Printable list", count: 0
      end

      fresh = create_world_form("Trip Sizes")
      as(:admin) do
        get form_path(fresh)
        items = css_select("#actions .dropdown-menu li:not(.d-md-none)").map { |item| item.text.strip }
        assert_equal [ "Preview as…", "Duplicate", "Archive", "Delete" ], items
        assert_select "#actions .dropdown-menu button.text-danger", text: "Delete"
        assert_select "#actions .dropdown-menu form[data-turbo-confirm] button", text: "Archive"
        assert_select "#actions .dropdown-menu button.text-danger", text: "Archive", count: 0
        assert_select "#actions .dropdown-menu li.d-md-none", text: /Remind/, msg: "on phones Remind folds into More"
      end

      @form.form_badge_grants.create!(badge: @health_officer_badge, access: :read)
      as(:health_officer) do
        get form_path(@form)
        assert_response :success
        assert_select "tr#person_#{person(:a1).id}"
        assert_select "#actions", count: 0
        assert_select "a", text: "Edit", count: 0
        assert_select ".screen-state-line a", count: 0
      end
    end
  end

  test "taking answers is a choice on the edit page, and opening sends nothing" do
    form = create_world_form("Trip", include: [], status: :draft)
    with_feature do
      as(:pack_leader) do
        get form_path(form)
        assert_select ".screen-state-line", text: /Not taking answers yet/
        assert_select ".screen-state-line a[href=?]", edit_form_path(form, tab: "responses"), text: "Start taking answers"

        get edit_form_path(form, tab: "responses")
        assert_select "input[type=radio][name=?]", "form[status]", count: 3
        assert_select "input[type=radio][name=?][value=draft][checked]", "form[status]"
        assert_select ".card-footer a.btn-secondary", text: "Cancel"
        assert_select ".card-footer a", text: "Back", count: 0

        patch form_path(form), params: { tab: "responses", form: { status: "open" } }
        assert_response :unprocessable_entity
        assert_select ".invalid-feedback", text: /Add someone to ask before opening the form/
        assert form.reload.draft?

        add_rule(form, @pack)
        deadline = 3.days.from_now
        form.update!(closes_at: deadline)
        assert_no_emails do
          assert_no_enqueued_jobs do
            patch form_path(form), params: { tab: "responses", form: { status: "open" } }
          end
        end
        assert_redirected_to edit_form_path(form, tab: "responses")
        assert form.reload.open?
        assert_empty form.form_reminders
        get form_path(form)
        assert_select ".screen-state-line", text: /Taking answers until #{Regexp.escape(deadline.strftime("%B %-d, %Y"))}/
        assert_select ".screen-state-line a", count: 0

        patch form_path(form), params: { tab: "responses", form: { status: "closed" } }
        assert form.reload.closed?
        get form_path(form)
        assert_select ".screen-state-line", text: /Closed/
        assert_select ".screen-state-line a", text: "Start taking answers"

        patch form_path(form), params: { tab: "responses", form: { status: "draft" } }
        assert form.reload.draft?

        form.update!(status: :archived)
        patch form_path(form), params: { tab: "responses", form: { status: "open" } }
        assert form.reload.archived?, "archiving is its own action, not undone here"
      end
    end
  end

  test "only people who manage the form change whether it takes answers" do
    draft = create_world_form("Trip", status: :draft)
    with_feature do
      as(:den_a_leader) do
        patch form_path(draft), params: { tab: "responses", form: { status: "open" } }
        assert draft.reload.draft?, "Den A's leader doesn't manage the Pack form"
        patch form_path(@form), params: { tab: "responses", form: { status: "closed" } }
        assert @form.reload.open?
      end
      as(:pack_leader) do
        patch form_path(draft), params: { tab: "responses", form: { status: "open" } }
        assert draft.reload.open?, "the same change from someone who manages it"
      end
    end
  end

  test "taking answers refuses a choice the form's own times would undo" do
    form = create_world_form("Trip")
    form.update_columns(opens_at: 1.day.ago)
    with_feature do
      as(:pack_leader) do
        patch form_path(form), params: { tab: "responses", form: { status: "draft" } }
        assert_response :unprocessable_entity
        assert_select ".invalid-feedback", text: "Opens is in the past: change it or choose No, closed."
        assert form.reload.open?

        patch form_path(form), params: { tab: "responses", form: { status: "draft", opens_at: 2.days.from_now.iso8601 } }
        assert form.reload.draft?, "a new Opens time lets it wait"

        form.update_columns(status: Form.statuses[:closed], opens_at: nil, closes_at: 1.hour.ago)
        patch form_path(form), params: { tab: "responses", form: { status: "open" } }
        assert_response :unprocessable_entity
        assert_select ".invalid-feedback", text: "The deadline has passed: move it first."
        assert form.reload.closed?

        patch form_path(form), params: { tab: "responses", form: { status: "open", closes_at: 3.days.from_now.iso8601 } }
        assert form.reload.open?
      end
    end
  end

  test "the header gives the date once, in the state line" do
    @form.update_columns(status: Form.statuses[:closed], closes_at: 2.days.ago)
    with_feature do
      as(:pack_leader) do
        get form_path(@form)
        assert_select ".card-header", text: /Due/, count: 0
        assert_select ".screen-state-line", text: /Closed #{Regexp.escape(2.days.ago.strftime("%B %-d, %Y"))}/
      end
    end
  end

  test "more choices stays closed while everything in it is the default" do
    with_feature do
      as(:pack_leader) do
        everything = @form.answerable_questions.map(&:id)
        get form_path(@form, team_id: @den_a.id, columns_for: @form.id, question_ids: everything)
        assert_select "details#more-choices:not([open])"
        assert_select "#status-filter a[href=?]", form_path(@form, team_id: @den_a.id, status: "complete")

        get form_path(@form, columns_for: @form.id, question_ids: [ @note.id ])
        assert_select "details#more-choices[open]"
        get form_path(@form, version: "latest")
        assert_select "details#more-choices[open]"
      end
    end
  end

  test "who to include loads its choices only when they're asked for" do
    with_feature do
      as(:pack_leader) do
        get form_path(@form)
        assert_select "input[name=who]", count: 0
        assert_select "turbo-frame#who_to_include[loading=lazy][src=?]", form_path(@form, frame: "who_to_include")

        get form_path(@form, frame: "who_to_include")
        assert_response :success
        assert_select "turbo-frame#who_to_include input[type=radio][name=who][value=asked][checked]"
        assert_select "turbo-frame#who_to_include select#question_form_id option", text: "Meal Choices"
        assert_no_match(/<html/, response.body, "just the frame")

        get form_path(@form, who: "answered", question_id: @sandwich.id, answers: { @sandwich.id => [ "Slim 4" ] })
        assert_select "turbo-frame#who_to_include", count: 0
        assert_select "input[type=radio][name=who][value=answered][checked]"
      end
    end
  end

  test "people picked from another form that this form doesn't ask are listed as not answered" do
    snacks = create_world_form("Snacks", include: [ @den_a ])
    add_choice(snacks, "Snack", [ "Chips" ])
    respond(snacks, :a1, as: :a1, answers: { "snack" => "Chips" })
    picked = { who: "answered", question_form_id: @form.id, question_id: @sandwich.id, answers: { @sandwich.id => [ "Slim 4", "Big John" ] } }
    with_feature do
      as(:pack_leader) do
        get form_path(snacks, picked)
        assert_select "p", text: /People: 2 who answered/
        assert_select "tr#person_#{person(:a1).id} td", text: "Chips"
        assert_select "#havent-answered", text: "Haven't answered (1)"
        assert_select "tr#person_#{person(:b1).id} td", text: "B1 World"
        assert_select "#labels .fw-bold", text: "B1 World"

        get form_path(snacks, picked.merge(team_id: @den_a.id))
        assert_select "#havent-answered", count: 0, msg: "the team filter applies to them too"
        get form_path(snacks, picked.merge(status: "complete"))
        assert_select "#havent-answered", count: 0, msg: "they have no status to match"
      end
    end
  end

  test "people picked whose answers on this form the viewer can't see are counted" do
    poll = create_world_form("Lunch Poll", read: "everyone")
    lunch = add_choice(poll, "Lunch", [ "Yes", "No" ])
    respond(poll, :a1, as: :a1, answers: { "lunch" => "Yes" })
    respond(poll, :b1, as: :b1, answers: { "lunch" => "Yes" })
    private_meals = create_world_form("Private Meals", respond: "self", read: "self_and_leaders")
    with_feature do
      as(:den_a_leader) do
        get form_path(private_meals, who: "answered", question_form_id: poll.id, question_id: lunch.id, answers: { lunch.id => [ "Yes" ] })
        assert_response :success
        assert_select "tr#person_#{person(:a1).id}"
        assert_select "tr#person_#{person(:b1).id}", count: 0
        assert_select "#not-shown", text: "Not shown: 1 person whose answers you can't see."
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
