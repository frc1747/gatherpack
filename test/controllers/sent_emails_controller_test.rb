require "test_helper"
require_relative "../support/email_log_test_helper"

class SentEmailsControllerTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers
  include EmailLogTestHelper

  setup do
    @admin = users(:one)
    @admin.update!(admin: true)
    gateway = resend_gateway
    @to_bob = SentEmail.create!(gateway: gateway, person: people(:two), address: "bob@example.com",
      subject: "Practice moved", status: "delivered", sent_at: 2.hours.ago, about: announcements(:one))
    @bounced = SentEmail.create!(gateway: gateway, address: "nobody@example.com",
      subject: "Weekly summary", status: "bounced", sent_at: 1.hour.ago, problem_detail: "Mailbox does not exist")
  end

  test "admins see every sent email, newest first" do
    sign_in @admin

    get sent_emails_url

    assert_response :success
    assert_select "h1", "Sent email"
    rows = css_select("#sent_emails tbody tr").map { |row| row["id"] }
    assert_equal [ ActionView::RecordIdentifier.dom_id(@bounced), ActionView::RecordIdentifier.dom_id(@to_bob) ], rows
    assert_select "td", text: /Mailbox does not exist/
    assert_select "a[href=?]", person_path(people(:two))
  end

  test "filters by status, person, about and words" do
    sign_in @admin

    get sent_emails_url, params: { q: { status_eq: "bounced" } }
    assert_select "#sent_emails tbody tr", 1
    assert_select "##{ActionView::RecordIdentifier.dom_id(@bounced)}"

    get sent_emails_url, params: { q: { person_id_eq: people(:two).id } }
    assert_select "#sent_emails tbody tr", 1
    assert_select "##{ActionView::RecordIdentifier.dom_id(@to_bob)}"

    get sent_emails_url, params: { q: { about_type_eq: "Announcement" } }
    assert_select "#sent_emails tbody tr", 1
    assert_select "##{ActionView::RecordIdentifier.dom_id(@to_bob)}"

    get sent_emails_url, params: { q: { address_or_subject_i_cont: "weekly" } }
    assert_select "#sent_emails tbody tr", 1
    assert_select "##{ActionView::RecordIdentifier.dom_id(@bounced)}"
  end

  test "status labels on the screen follow their settings" do
    Settings[:email_log_status_bounced_label] = "Returned"
    sign_in @admin

    get sent_emails_url

    assert_select "td", text: /Returned/
  end

  test "people who aren't admins are turned away" do
    sign_in users(:two)

    get sent_emails_url

    assert_redirected_to root_path
  end

  test "the screen and its Setup button are hidden when the feature is off" do
    sign_in @admin

    get setup_url
    assert_select "a[href=?]", sent_emails_path

    turn_off_email_log

    get setup_url
    assert_select "a[href=?]", sent_emails_path, count: 0

    get sent_emails_url
    assert_redirected_to root_path
  end
end
