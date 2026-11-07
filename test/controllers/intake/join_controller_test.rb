require "test_helper"
require_relative "../../support/intake_world"

class Intake::JoinControllerTest < ActionDispatch::IntegrationTest
  include IntakeWorld
  include ActiveJob::TestHelper
  include Devise::Test::IntegrationHelpers

  setup do
    host! "localhost"
    build_intake_world
  end

  test "the form shows the registration's teams" do
    with_intake { get intake_join_path(@registration.slug) }

    assert_response :success
    assert_select "h1", "Join Northwind"
    assert_select "input[name='entry[team_ids][]']", 3
    assert_select "input[name=website]"
    assert_select "meta[name=robots][content*=noindex]"
  end

  test "an unknown, closed, not yet open or switched-off registration all say the same" do
    bodies = []
    with_intake do
      get intake_join_path("no-such-link")
      bodies << [ response.status, css_select("h1").text ]
      @registration.update!(closes_at: 1.minute.ago)
      get intake_join_path(@registration.slug)
      bodies << [ response.status, css_select("h1").text ]
      @registration.update!(opens_at: 1.day.from_now, closes_at: 2.days.from_now)
      get intake_join_path(@registration.slug)
      bodies << [ response.status, css_select("h1").text ]
    end
    @registration.update!(opens_at: 1.day.ago)
    get intake_join_path(@registration.slug)
    bodies << [ response.status, css_select("h1").text ]

    assert_equal [ [ 404, "Registration has closed." ] ], bodies.uniq
  end

  test "a closed registration names its successor's open date" do
    successor = Intake::Registration.create!(team: @northwind, title: "Next", opens_at: 60.days.from_now, apply_team_ids: [ @juniors.id ])
    @registration.update!(closes_at: 1.minute.ago, successor: successor)

    with_intake { get intake_join_path(@registration.slug) }

    assert_match "The next one opens on", response.body
  end

  test "signing up makes an entry only, and no person or login before the email is confirmed" do
    with_intake do
      assert_no_difference -> { Person.count + User.count + MembershipApplication.count + Relationship.count } do
        assert_difference -> { Intake::Entry.count } do
          assert_enqueued_with(job: Intake::EntryEmailJob) do
            post intake_join_path(@registration.slug), params: join_params(email: " Riley@Example.com ")
          end
        end
      end
    end

    assert_response :success
    assert_select "h1", "Thanks, Riley. Check your email to finish."
    entry = Intake::Entry.last
    assert_equal "riley@example.com", entry.email
    assert_equal [ @juniors.id ], entry.team_ids
    assert entry.source_link?
    assert_equal "127.0.0.*", entry.created_ip_prefix
    assert_nil entry.person
    assert_empty flash.to_h
  end

  test "the entry's audit row is attributed to the entry" do
    with_intake { post intake_join_path(@registration.slug), params: join_params }

    entry = Intake::Entry.last
    assert_equal entry.id, AuditLog.where(item_type: "Intake::Entry", item_id: entry.id).last.whodunnit
  end

  test "an email with a login and a new one get the same page, status and queries" do
    existing = create_intake_person("Casey", "Quinn", email: "casey@example.com")
    responses = []
    counts = []

    with_intake do
      # Warm up anything a first request loads once per process.
      post intake_join_path(@registration.slug), params: join_params(email: "warm.up@example.com")
      [ existing.user.email, "someone.new@example.com" ].each do |email|
        statements = sql_statements { post intake_join_path(@registration.slug), params: join_params(first_name: "Casey", email: email) }
        responses << [ response.status, response.body.gsub(/name="authenticity_token" value="[^"]+"/, "").gsub(/content="[^"]+" name="csrf-token"|name="csrf-token" content="[^"]+"/, "") ]
        counts << statements.size
        assert_not statements.any? { |sql| sql.include?(%("users")) }, "the request must not look up users"
      end
    end

    assert_equal responses.first, responses.last
    assert_equal counts.first, counts.last
  end

  test "the email job decides: a login gets a sign-in email, a new address gets a link" do
    existing = create_intake_person("Casey", "Quinn", email: "casey@example.com")
    known, = create_intake_entry(first_name: "Casey", email: "CASEY@example.com")
    unknown, = create_intake_entry(email: "new.person@example.com")
    known.update!(token_digest: nil)

    Intake::EntryEmailJob.perform_now(known)
    Intake::EntryEmailJob.perform_now(unknown)
    sent = enqueued_jobs.select { |job| job[:job] == SendEmailJob }.map { |job| job[:args] }

    assert_equal [ "CASEY@example.com", "new.person@example.com" ], sent.map(&:second)
    assert_match "You already have an account. Sign in to continue", sent.first.fourth
    assert_nil known.reload.token_digest
    assert_match "Finish joining Juniors", sent.last.third
    assert_match "/join/verify?token=", sent.last.fourth
    assert unknown.reload.token_digest
    assert_not_includes sent.map(&:fourth).join, existing.last_name
  end

  test "too many sign-ups from one address" do
    with_intake(intake_rate_ip_per_hour: "2") do
      3.times { |i| post intake_join_path(@registration.slug), params: join_params(email: "p#{i}@example.com") }
    end

    assert_response :too_many_requests
    assert_match "Try again in a few minutes.", response.body
    assert_equal 2, Intake::Entry.count
  end

  test "too many sign-ups for one email" do
    with_intake(intake_rate_email_per_hour: "1") do
      post intake_join_path(@registration.slug), params: join_params(email: "same@example.com")
      post intake_join_path(@registration.slug), params: join_params(email: "SAME@example.com"), headers: { "REMOTE_ADDR" => "10.0.0.9" }
    end

    assert_response :too_many_requests
    assert_equal 1, Intake::Entry.count
  end

  test "too many sign-ups for one registration" do
    with_intake(intake_rate_registration_per_hour: "1") do
      post intake_join_path(@registration.slug), params: join_params(email: "a@example.com")
      post intake_join_path(@registration.slug), params: join_params(email: "b@example.com"), headers: { "REMOTE_ADDR" => "10.0.0.9" }
    end

    assert_response :too_many_requests
    assert_equal 1, Intake::Entry.count
  end

  test "a filled honeypot is dropped quietly" do
    with_intake do
      assert_no_difference -> { Intake::Entry.count } do
        post intake_join_path(@registration.slug), params: join_params.merge(website: "http://spam.example")
      end
    end

    assert_response :success
    assert_select "h1", "Thanks, Riley. Check your email to finish."
    assert_no_enqueued_jobs only: Intake::EntryEmailJob
  end

  test "a form sent back too fast, or without its timestamp, is dropped quietly" do
    with_intake do
      assert_no_difference -> { Intake::Entry.count } do
        post intake_join_path(@registration.slug), params: join_params(started: 1.second.ago)
        assert_select "h1", "Thanks, Riley. Check your email to finish."
        post intake_join_path(@registration.slug), params: join_params.merge(started: "forged")
        assert_select "h1", "Thanks, Riley. Check your email to finish."
      end
    end
  end

  test "an installed bot check that fails is dropped quietly" do
    failing = Class.new(Intake::BotCheck::None) { def passed?(*) = false }.new
    Intake::BotCheck.adapter = failing

    with_intake do
      assert_no_difference -> { Intake::Entry.count } do
        post intake_join_path(@registration.slug), params: join_params
      end
    end
  ensure
    Intake::BotCheck.adapter = nil
  end

  test "at the cap, new people are told the registration is busy and managers hear once" do
    create_intake_entry(email: "one@example.com")
    create_intake_entry(email: "two@example.com")

    with_intake(intake_entry_cap: "2") do
      assert_no_difference -> { Intake::Entry.count } do
        assert_enqueued_jobs @northwind.all_managers_and_admins.count, only: SendEmailJob do
          post intake_join_path(@registration.slug), params: join_params(email: "three@example.com")
          post intake_join_path(@registration.slug), params: join_params(email: "four@example.com")
        end
      end
    end

    assert_response :service_unavailable
    assert_select "h1", "Registration is busy. Try again later."
  end

  test "a missing name or bad email shows the form again" do
    with_intake { post intake_join_path(@registration.slug), params: join_params(first_name: "", email: "not-an-email") }

    assert_response :unprocessable_content
    assert_equal 0, Intake::Entry.count
  end

  test "teams outside the registration can't be chosen" do
    with_intake { post intake_join_path(@registration.slug), params: join_params(teams: [ @families ]) }

    assert_response :unprocessable_content
    assert_match "Choose at least one team.", response.body
  end

  test "signed in, joining applies at once" do
    person = create_intake_person("Casey", "Quinn", birthday: 30.years.ago.to_date)
    sign_in person.user

    with_intake { post intake_join_path(@registration.slug), params: { entry: { team_ids: [ @mentors.id ] } } }

    assert_redirected_to intake_me_path(@registration.slug)
    application = person.membership_applications.sole
    assert_equal [ @mentors, @registration ], [ application.team, application.registration ]
    assert application.source_link?
  end

  test "what people type stays out of the log" do
    filter = ActiveSupport::ParameterFilter.new(Rails.application.config.filter_parameters)
    filtered = filter.filter("entry" => { "email" => "a@b.c", "first_name" => "Riley" }, "guardian_email" => "g@b.c", "token" => "abc", "password" => "x", "answers" => "y")

    assert_equal "[FILTERED]", filtered["entry"]["email"]
    assert_equal "[FILTERED]", filtered["guardian_email"]
    assert_equal "[FILTERED]", filtered["token"]
    assert_equal "[FILTERED]", filtered["password"]
    assert_equal "[FILTERED]", filtered["answers"]
  end
end
