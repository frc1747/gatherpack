require "application_system_test_case"

# List links leave the "results" Turbo Frame with data-turbo-frame="_top".
# They must arrive, show no "Content missing", and stay a Turbo visit (a marker
# set on window survives; a full document load would clear it).
class FrameLinksTest < ApplicationSystemTestCase
  include Warden::Test::Helpers

  # The test environment only allows the host "localhost".
  Capybara.server_host = "localhost"

  # Pages holding a list of links. Teams list only the viewer's teams by default.
  PAGES = {
    people: -> { people_path },
    teams: -> { teams_path(filter: "all") },
    team_types: -> { team_types_path },
    relationship_types: -> { relationship_types_path },
    events: -> { events_path },
    event_types: -> { event_types_path },
    badge_types: -> { badge_types_path },
    badges: -> { badges_path },
    tokens: -> { tokens_path },
    announcements: -> { announcements_path },
    questions: -> { questions_path },
    hooks: -> { hooks_path },
    reports: -> { reports_path },
    variables: -> { variables_path },
    shortcuts: -> { shortcuts_path },
    pages: -> { pages_path },
    mailboxes: -> { mailboxes_path },
    checkin_fields: -> { checkin_fields_path },
    calendar_notes: -> { calendar_notes_path },
    ledgers: -> { ledgers_path },
    ledger_tags: -> { ledger_tags_path },
    ledger_entry_links: -> { ledger_entry_links_path },
    budgets: -> { budgets_path },
    budget_periods: -> { budget_periods_path },
    oauth_applications: -> { oauth_applications_path },
    audit_logs: -> { audit_logs_path },
    time_clock_periods: -> { time_clock_periods_path },
    time_clock_punches: -> { time_clock_punches_path },
    team_memberships: -> { team_memberships_path(teams(:one)) },
    badge_assignments: -> { badge_badge_assignments_path(badges(:one)) },
    ledger_ownerships: lambda {
      LedgerOwnership.destroy_all # the fixtures name an owner class that doesn't exist
      LedgerOwnership.create!(ledger: ledgers(:one), owner: people(:one))
      ledger_ownerships_path(ledgers(:one))
    },
    mailbox_messages: -> { mailbox_path(mailboxes(:one)) },
    event_checkins: -> { event_path(events(:one)) }
  }.freeze

  # Pages that raise before rendering on the current base: `as_badge` is called
  # with a positional argument. Unskip once that is fixed.
  UNCOVERED = %i[calendar_notes].freeze

  # Ransack 6 needs this on each model before its index renders; the base
  # leaves it out. Stubbed here so the pages can be clicked through.
  RANSACK_MODELS = [ Hook, Mailbox, MailboxMessage, Variable, Report, EventType, TeamType ].freeze

  setup do
    RANSACK_MODELS.each do |model|
      model.singleton_class.define_method(:ransackable_associations) { |_auth = nil| [] }
    end
    MailboxAssignment.delete_all # the fixtures name a target class that doesn't exist
    admin = User.create!(email: "frame-admin@example.com", password: "Password1!", admin: true, architect: true)
    Person.create!(user: admin, first_name: "Ada", last_name: "Admin")
    login_as admin, scope: :user
  end

  teardown do
    Warden.test_reset!
    RANSACK_MODELS.each { |model| model.singleton_class.remove_method(:ransackable_associations) }
    $frame_link_runs = nil
  end

  PAGES.each do |name, path|
    test "a row link on #{name} is a Turbo visit" do
      skip "#{name} does not render on this base" if UNCOVERED.include?(name)

      page_path = instance_exec(&path)
      visit page_path
      page.execute_script("window.frameLinkMarker = true")

      find("#results :is(.card-header, td) a:not(.dropdown-item), :is(.card-header, td) a:not(.dropdown-item)", match: :first).click

      assert_no_current_path page_path, ignore_query: true
      assert_no_text "Content missing"
      assert_no_text "Application error"
      assert page.evaluate_script("window.frameLinkMarker"), "#{name} link caused a full page load"
    end
  end

  test "Run on a report is a Turbo visit and shows its output" do
    Report.destroy_all
    Report.create!(name: "Probe", code: "{ ok: true }")
    visit reports_path
    page.execute_script("window.frameLinkMarker = true")

    find("#results a", text: "Run", match: :first).click

    assert_no_current_path reports_path, ignore_query: true
    assert_selector "pre"
    assert_no_text "Content missing"
    assert page.evaluate_script("window.frameLinkMarker"), "Run caused a full page load"
  end

  test "hovering Run does not execute the report" do
    report = Report.create!(name: "Hover probe", code: "$frame_link_runs = ($frame_link_runs || 0) + 1\n{ ok: true }")

    [ reports_path, report_path(report), run_report_path(report) ].each do |path|
      visit path
      $frame_link_runs = nil # visiting the run page itself runs the report
      find("a", text: "Run", match: :first).hover
      sleep 0.5 # Turbo prefetches a hovered link after a short delay

      assert_nil $frame_link_runs, "hovering Run on #{path} executed the report"
    end
  end
end
