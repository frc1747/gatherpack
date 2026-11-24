require "test_helper"

class PagePolicyTest < ActiveSupport::TestCase
  setup do
    @pack = Team.create!(name: "Pack", team_type: team_types(:one))
    @den = Team.create!(name: "Den", team_type: team_types(:one), parent: @pack)
    @other = Team.create!(name: "Other", team_type: team_types(:one))

    @member = create_person("member@example.com")
    Membership.create!(person: @member, team: @den)
    @den_leader = create_person("den-leader@example.com")
    Membership.create!(person: @den_leader, team: @den, manager: true)
    @pack_leader = create_person("pack-leader@example.com")
    Membership.create!(person: @pack_leader, team: @pack, manager: true)
    @other_leader = create_person("other-leader@example.com")
    Membership.create!(person: @other_leader, team: @other, manager: true)
    @admin = create_person("admin@example.com", admin: true)

    @pages = Page::PERMISSION_LEVELS.flat_map do |viewer|
      [ @den, @other, nil ].map do |team|
        page = Page.new(title: [ viewer, team&.name ].compact.join(" "), content: "x", viewer: viewer, editor: "admin", team: team)
        page.save!(validate: false)
        page
      end
    end
    @pages << pages(:one) # an unknown viewer level
  end

  def test_scope
    [ @member, @den_leader, @pack_leader, @other_leader, @admin ].each do |viewer|
      visible = PagePolicy::Scope.new(viewer.user, Page).resolve

      @pages.each do |page|
        assert_equal PagePolicy.new(viewer.user, page).show?, visible.exists?(page.id),
          "#{viewer.user.email}: scope and show? disagree on the #{page.viewer} page of #{page.team&.name || 'no team'}"
      end
    end

    visible = PagePolicy::Scope.new(nil, Page).resolve
    @pages.each do |page|
      assert_equal PagePolicy.new(nil, page).show?, visible.exists?(page.id),
        "signed out: scope and show? disagree on the #{page.viewer} page of #{page.team&.name || 'no team'}"
    end
  end

  def test_show
    assert_equal [ "public den", "user den", "team den" ], visible_titles(@member, team: @den)
    assert_equal [ "public den", "user den", "team den", "manager den" ], visible_titles(@den_leader, team: @den)
    assert_equal [ "public den", "user den", "team den", "manager den" ], visible_titles(@pack_leader, team: @den)
    assert_equal [ "public den", "user den" ], visible_titles(@other_leader, team: @den)
    assert_equal [ "public den", "user den", "team den", "manager den", "admin den" ], visible_titles(@admin, team: @den)
    assert_equal [ "public den" ], visible_titles(nil, team: @den)
    assert_not PagePolicy.new(@den_leader.user, page_titled("manager")).show?
    assert_not PagePolicy.new(@den_leader.user, pages(:one)).show?
    assert PagePolicy.new(@admin.user, pages(:one)).show?
  end

  def test_create
  end

  def test_update
  end

  def test_destroy
  end

  private

  def visible_titles(viewer, team:)
    @pages.select { |page| page.team == team && PagePolicy.new(viewer&.user, page).show? }.map { |page| page.title.downcase }
  end

  def page_titled(title)
    @pages.find { |page| page.title == title }
  end

  def create_person(email, admin: false)
    user = User.create!(email: email, password: "Password1!", admin: admin)
    Person.create!(user: user, first_name: "Test", last_name: "Person")
  end
end
