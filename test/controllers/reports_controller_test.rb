require "test_helper"

class ReportsControllerTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers

  setup do
    host! "localhost"

    @admin = create_user("admin@example.com", admin: true)
    @architect = create_user("architect@example.com", admin: true, architect: true)
    @report = Report.create!(name: "Roster", code: "Person.count")
  end

  test "an admin who isn't an architect can't delete a report" do
    sign_in @admin

    delete report_path(@report)

    assert Report.exists?(@report.id), "a non-architect admin deleted a report"
  end

  test "an architect can delete a report" do
    sign_in @architect

    delete report_path(@report)

    assert_not Report.exists?(@report.id)
    assert_redirected_to reports_path
  end

  test "the report pages offer Delete only to architects" do
    sign_in @admin
    get report_path(@report)
    assert_response :success
    assert_select "a[href=?][data-turbo-method=delete]", report_path(@report), count: 0
    get run_report_path(@report)
    assert_response :success
    assert_select "a[href=?][data-turbo-method=delete]", report_path(@report), count: 0

    sign_in @architect
    get report_path(@report)
    assert_select "a[href=?][data-turbo-method=delete]", report_path(@report), count: 1
    get run_report_path(@report)
    assert_select "a[href=?][data-turbo-method=delete]", report_path(@report), count: 1
  end

  private

  def create_user(email, **flags)
    user = User.create!(email: email, password: "Password1!", **flags)
    Person.create!(user: user, first_name: "Test", last_name: "Person")
    user
  end
end
