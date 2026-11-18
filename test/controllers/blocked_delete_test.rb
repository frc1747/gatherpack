require "test_helper"

class BlockedDeleteTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers

  setup do
    host! "localhost"

    @admin_user = User.create!(email: "admin@example.com", password: "Password1!", admin: true)
    Person.create!(user: @admin_user, first_name: "Ada", last_name: "Admin")
    sign_in @admin_user
  end

  test "deleting a team that still has a ledger redirects with an alert" do
    team = teams(:one)
    ledger = ledgers(:one)

    assert_no_difference [ "Team.count", "Ledger.count" ] do
      delete team_url(team), headers: { "HTTP_REFERER" => team_url(team) }
    end

    assert_redirected_to team_url(team)
    assert_equal "This can't be deleted while other records still use it.", flash[:alert]
    assert Team.exists?(team.id)
    assert Ledger.exists?(ledger.id)
  end

  test "a refused delete shows the record's own errors" do
    # Upstream has no restrict_with_error association, so make Badge refuse
    # the way one does (errors on the record, RecordNotDestroyed raised).
    badge = badges(:one)
    original = Badge.instance_method(:destroy!)
    Badge.define_method(:destroy!) do
      errors.add(:base, "Cannot delete record because dependent assignments exist")
      raise ActiveRecord::RecordNotDestroyed.new("Failed to destroy the record", self)
    end

    assert_no_difference "Badge.count" do
      delete badge_url(badge)
    end

    assert_redirected_to root_url
    assert_equal "Cannot delete record because dependent assignments exist", flash[:alert]
    assert Badge.exists?(badge.id)
  ensure
    Badge.define_method(:destroy!, original)
  end
end
