require "test_helper"

class TokensControllerTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers

  setup do
    host! "localhost"

    @team = Team.create!(name: "Robotics", team_type: team_types(:one))
    @other_team = Team.create!(name: "Drama", team_type: team_types(:one))

    @admin_user, @admin = create_person("admin", admin: true)
    @manager_user, @manager = create_person("manager", team: @team, manager: true)
    _, @member = create_person("member", team: @team)
    _, @outsider = create_person("outsider", team: @other_team)
    _, @plain_admin = create_person("plain-admin", team: @team, admin: true)
  end

  # --- create -------------------------------------------------------------

  test "a manager can issue a card to a member they manage" do
    sign_in @manager_user

    assert_difference -> { Token.count }, 1 do
      post tokens_path, params: { token: { value: "424240", tokenable_nid: @member.neat_id.to_s } }
    end
    assert_equal @member, Token.find_by!(value: "424240").tokenable
  end

  test "a manager can issue a card to themselves" do
    sign_in @manager_user

    assert_difference -> { Token.count }, 1 do
      post tokens_path, params: { token: { value: "424241", tokenable_nid: @manager.neat_id.to_s } }
    end
  end

  test "a manager cannot issue a card to someone outside their teams" do
    sign_in @manager_user

    post tokens_path, params: { token: { value: "424242", tokenable_nid: @outsider.neat_id.to_s } }

    assert_nil Token.find_by(value: "424242"), "a manager issued a card to a person they don't manage"
    assert_redirected_to root_path
  end

  test "a manager cannot issue a card to an admin" do
    sign_in @manager_user

    post tokens_path, params: { token: { value: "434343", tokenable_nid: @admin.neat_id.to_s } }

    assert_nil Token.find_by(value: "434343"), "a manager issued a card bound to an admin"
  end

  test "an admin can issue a card to anyone" do
    sign_in @admin_user

    assert_difference -> { Token.count }, 1 do
      post tokens_path, params: { token: { value: "444444", tokenable_nid: @outsider.neat_id.to_s } }
    end
  end

  test "an unknown holder id shows the form again" do
    sign_in @admin_user

    assert_no_difference -> { Token.count } do
      post tokens_path, params: { token: { value: "454545", tokenable_nid: "per_doesnotexist" } }
    end
    assert_response :unprocessable_entity
  end

  # --- update -------------------------------------------------------------

  test "a manager cannot reassign a managed member's card to an outsider" do
    token = Token.create!(value: "555001", tokenable: @member)
    sign_in @manager_user

    patch token_path(token), params: { token: { tokenable_nid: @outsider.neat_id.to_s } }

    assert_equal @member, token.reload.tokenable, "a manager reassigned a card to a person outside their teams"
  end

  test "a manager can reassign a card between members they manage" do
    token = Token.create!(value: "555002", tokenable: @member)
    sign_in @manager_user

    patch token_path(token), params: { token: { tokenable_nid: @manager.neat_id.to_s } }

    assert_redirected_to token_path(token)
    assert_equal @manager, token.reload.tokenable
  end

  test "a manager cannot change or delete the card of an admin on their team" do
    token = Token.create!(value: "555003", tokenable: @plain_admin)
    sign_in @manager_user

    patch token_path(token), params: { token: { tokenable_nid: @member.neat_id.to_s } }
    assert_equal @plain_admin, token.reload.tokenable

    assert_no_difference -> { Token.count } do
      delete token_path(token)
    end
  end

  test "an admin can reassign any card" do
    token = Token.create!(value: "555004", tokenable: @member)
    sign_in @admin_user

    patch token_path(token), params: { token: { tokenable_nid: @outsider.neat_id.to_s } }

    assert_equal @outsider, token.reload.tokenable
  end

  test "an unknown holder id leaves the card as it was" do
    token = Token.create!(value: "555005", tokenable: @member)
    sign_in @admin_user

    patch token_path(token), params: { token: { value: "555006", tokenable_nid: "per_doesnotexist" } }

    assert_response :unprocessable_entity
    token.reload
    assert_equal "555005", token.value
    assert_equal @member, token.tokenable
  end

  # --- duplicate values ----------------------------------------------------

  test "a second card with an existing card's value cannot be created in the other reader's format" do
    existing = Token.create!(value: "8675309", tokenable: @member)
    sign_in @manager_user

    post tokens_path, params: { token: { value: "5700" + 8675309.to_s(16), tokenable_nid: @manager.neat_id.to_s } }

    assert_equal 1, Token.where(value: "8675309").count,
      "two tokens share the stored value 8675309, so the kiosk would pick one arbitrarily"
    assert_redirected_to edit_token_path(existing)
  end

  test "a card cannot be changed to another card's value in the other reader's format" do
    Token.create!(value: "8675309", tokenable: @member)
    token = Token.create!(value: "424242", tokenable: @manager)
    sign_in @manager_user

    patch token_path(token), params: { token: { value: "5700" + 8675309.to_s(16) } }

    assert_response :unprocessable_entity
    assert_equal "424242", token.reload.value
    assert_equal 1, Token.where(value: "8675309").count
  end

  private

  def create_person(name, team: nil, manager: false, admin: false)
    user = User.create!(email: "#{name}@example.com", password: "Password1!", admin: admin)
    person = Person.create!(user: user, first_name: name.capitalize, last_name: "Test")
    Membership.create!(person: person, team: team, manager: manager) if team
    [ user, person ]
  end
end
