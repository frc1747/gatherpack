require "test_helper"

class WidgetTest < ActiveSupport::TestCase
  setup do
    @team = Team.create!(name: "Den A", team_type: team_types(:one))
    @member = create_person("member@example.com", manager: false)
    @manager = create_person("manager@example.com", manager: true)
    @outsider = User.create!(email: "outsider@example.com", password: "Password1!")
    Person.create!(user: @outsider, first_name: "Out", last_name: "Sider")
    @admin = User.create!(email: "admin@example.com", password: "Password1!", admin: true)
  end

  test "needs a title" do
    widget = Widget.new
    assert_not widget.valid?
    assert_includes widget.errors[:title], "can't be blank"
  end

  test "team and manager levels need a team" do
    %w[ team manager ].each do |viewer|
      widget = Widget.new(title: "Notice", viewer: viewer)
      assert_not widget.valid?, "#{viewer} without a team should be invalid"
      assert widget.errors[:team].any?
      widget.team = @team
      assert widget.valid?
    end
  end

  test "refresh is off or at least the minimum" do
    assert Widget.new(title: "A", refresh_seconds: 0).valid?
    assert_not Widget.new(title: "A", refresh_seconds: 10).valid?
    assert Widget.new(title: "A", refresh_seconds: 15).valid?
    assert_not Widget.new(title: "A", refresh_seconds: -1).valid?
  end

  test "placement, style mode and viewer come from their lists" do
    assert_not Widget.new(title: "A", placement: "middle").valid?
    assert_not Widget.new(title: "A", style_mode: "none").valid?
    assert_not Widget.new(title: "A", viewer: "public").valid?
  end

  test "everyone signed in sees a user-level widget" do
    widget = Widget.create!(title: "A", viewer: "user")
    assert widget.visible_to?(@outsider)
    assert_not widget.visible_to?(nil)
  end

  test "team level is for members of the team" do
    widget = Widget.create!(title: "A", viewer: "team", team: @team)
    assert widget.visible_to?(@member.user)
    assert widget.visible_to?(@manager.user)
    assert_not widget.visible_to?(@outsider)
  end

  test "manager level is for managers of the team" do
    widget = Widget.create!(title: "A", viewer: "manager", team: @team)
    assert widget.visible_to?(@manager.user)
    assert_not widget.visible_to?(@member.user)
  end

  test "admins see everything, including admin-only and disabled widgets" do
    admin_only = Widget.create!(title: "A", viewer: "admin")
    disabled = Widget.create!(title: "B", enabled: false)
    assert admin_only.visible_to?(@admin)
    assert disabled.visible_to?(@admin)
    assert_not admin_only.visible_to?(@manager.user)
    assert_not disabled.visible_to?(@member.user)
  end

  test "widgets are in the hook catalog" do
    assert_includes Hook.catalog, "widgets - create"
    assert_includes Hook.catalog, "widgets - update"
    assert_includes Hook.catalog, "widgets - destroy"
  end

  test "creating a widget runs its hooks" do
    Hook.create!(name: "Note widgets", event: "widgets - create", code: "model.update_column(:title, 'Hooked')")
    widget = Widget.create!(title: "A")
    assert_equal "Hooked", widget.reload.title
  end

  private

  def create_person(email, manager:)
    user = User.create!(email: email, password: "Password1!")
    person = Person.create!(user: user, first_name: email.split("@").first, last_name: "Test")
    Membership.create!(person: person, team: @team, manager: manager)
    person
  end
end
