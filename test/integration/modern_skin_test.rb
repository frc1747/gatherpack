require "test_helper"
require "support/modern_skin_test_settings"

class ModernSkinTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers
  include ModernSkinTestSettings

  NONCE_GENERATOR = "action_dispatch.content_security_policy_nonce_generator"
  NONCE_DIRECTIVES = "action_dispatch.content_security_policy_nonce_directives"
  ONE_PIXEL_PNG = "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNkYPhfDwAChwGA60e6kgAAAABJRU5ErkJggg=="

  setup do
    host! "localhost"
    @admin = create_user("admin@example.com", admin: true, first_name: "Ada")
    @member = create_user("member@example.com", first_name: "Jo")
  end

  # -- Rollback ---------------------------------------------------------------

  test "with the flag off the application layout is untouched" do
    sign_in @member
    get root_path
    assert_response :success
    assert_no_skin
  end

  test "with the flag off the devise layout is untouched" do
    get new_user_session_path
    assert_response :success
    assert_no_skin
    assert_select ".logoline"
  end

  test "with the flag off the kiosk layout is untouched" do
    sign_in @admin
    get time_kiosk_path
    assert_response :success
    assert_no_skin
  end

  test "with the flag off the sidebar has no color mode control" do
    sign_in @member
    get root_path
    assert_select "[data-controller=color-mode]", false
  end

  # -- Loading ----------------------------------------------------------------

  test "the skin link comes after the application stylesheet and before admin CSS" do
    Theme.instance.update!(custom_css: "body { margin: 0; }")

    with_skin do
      get new_user_session_path
      assert_response :success
      application = response.body.index(%r{<link[^>]*application-?[^>]*\.css})
      skin = response.body.index(%r{<link[^>]*skin-?[^>]*\.css})
      custom = response.body.index('id="theme-custom-css"')

      assert application && skin && custom, "expected all three in the head"
      assert_operator application, :<, skin
      assert_operator skin, :<, custom
    end
  end

  test "the inline script carries the nonce" do
    env_config = Rails.application.env_config
    original = env_config.slice(NONCE_GENERATOR, NONCE_DIRECTIVES)
    env_config[NONCE_GENERATOR] = ->(_request) { "test-nonce" }
    env_config[NONCE_DIRECTIVES] = %w[script-src]

    with_skin do
      get new_user_session_path
      assert_select "script[nonce=test-nonce]", /data-bs-theme/
    end
  ensure
    env_config.delete(NONCE_GENERATOR)
    env_config.delete(NONCE_DIRECTIVES)
    env_config.merge!(original)
  end

  test "the Inter font comes from this site" do
    css = Rails.root.join("app/assets/builds/skin.css").read
    assert_match %r{src: url\("/inter-latin-wght-normal\.woff2"\)}, css
    assert_no_match %r{https?://}, css
  end

  test "print resets both modes to the light palette" do
    css = Rails.root.join("app/assets/builds/skin.css").read
    print_block = css[/@media print \{.*?\n\}/m]

    assert print_block, "expected an @media print block"
    assert_includes print_block, ":root[data-bs-theme=dark]"
    assert_includes print_block, "--gp-page: #f5f6f7"
    assert_includes print_block, "--gp-text: #1c2024"
    assert_includes print_block, "color-scheme: light"
  end

  test "a report's print CSS variable comes out unchanged" do
    print_css = "@page { size: letter; } .page { color: #000; }"
    Variable.create!(name: "report_print_css", raw_value: print_css, klass: "string")
    page = Page.create!(title: "Report", editor: "admin", dynamic: true,
      content: %(<style><%= raw Variable.find_by(name: "report_print_css").value %></style>))

    sign_in @admin
    get page_path(page)
    assert_response :success
    plain = response.body[/<style>@page.*?<\/style>/m]

    with_skin do
      get page_path(page)
      assert_equal plain, response.body[/<style>@page.*?<\/style>/m]
    end
  end

  # -- Preview ----------------------------------------------------------------

  test "the theme page offers a preview while the skin is off" do
    sign_in @admin
    get edit_theme_path
    assert_select "form[action='#{skin_preview_path}'] button, form[action='#{skin_preview_path}'] input[type=submit]"
  end

  test "an admin previews the skin in their own session and can stop" do
    sign_in @admin
    post skin_preview_path
    assert_redirected_to edit_theme_path

    get root_path
    assert_skin_loaded
    assert_select ".skin-preview-note"

    delete skin_preview_path
    get root_path
    assert_no_skin
    assert_select ".skin-preview-note", false
  end

  test "the preview note goes away once the flag is on for everyone" do
    sign_in @admin
    post skin_preview_path

    with_skin do
      get root_path
      assert_skin_loaded
      assert_select ".skin-preview-note", false
    end
  end

  test "someone who isn't an admin can't start a preview" do
    sign_in @member
    post skin_preview_path
    get root_path
    assert_no_skin
  end

  test "a preview doesn't reach anyone else" do
    sign_in @admin
    post skin_preview_path
    get root_path
    assert_skin_loaded

    reset!
    host! "localhost"
    sign_in @member
    get root_path
    assert_no_skin
  end

  # -- Sign-in ----------------------------------------------------------------

  test "sign-in shows one card, the site title and a full-width button" do
    with_skin do
      with_setting(:title, "Northwind Scouts") do
        get new_user_session_path
      end
      assert_response :success
      assert_select ".logoline", false
      assert_select ".signin-title", "Northwind Scouts"
      assert_select ".card", 1
      assert_select ".card-header h2", "Sign in"
      assert_select "input[type=submit].w-100[value='Sign in']"
      assert_select "form[data-turbo=false]"
      assert_select "input[type=email]"
      assert_select "input[type=password]"
      assert_select "a", "Forgot your password?"
      assert_select "input[type=checkbox][name='user[remember_me]']"
      assert_select "footer.footer-ad", /powered by/
    end
  end

  test "sign-in without local auth has no password form" do
    with_skin do
      with_setting(:local_auth, "false") { get new_user_session_path }
      assert_response :success
      assert_select "input[type=password]", false
    end
  end

  test "sign-in offers sign up only when local signup is on" do
    with_skin do
      with_setting(:local_signup, "true") { get new_user_session_path }
      assert_select "a[href='#{new_user_registration_path}']", "Sign up"

      with_setting(:local_signup, "false") { get new_user_session_path }
      assert_select "a[href='#{new_user_registration_path}']", false
    end
  end

  test "sign-in keeps the omniauth partial" do
    registered = GatherPack::ViewOverrides.all
    GatherPack::ViewOverrides.register(:omniauth_marker,
      path: Rails.root.join("test/fixtures/files/view_overrides/omniauth_marker"), position: 20)

    with_skin do
      get new_user_session_path
      assert_response :success
      assert_match "omniauth partial rendered", response.body
    end
  ensure
    GatherPack::ViewOverrides.reset!
    registered.each { |o| GatherPack::ViewOverrides.register(o.key, path: o.path, position: o.position, active: o.active) }
  end

  test "sign-in shows the site logo when there is one" do
    Theme.instance.logo.attach(
      io: StringIO.new(Base64.decode64(ONE_PIXEL_PNG)),
      filename: "logo.png", content_type: "image/png"
    )

    with_skin do
      get new_user_session_path
      assert_response :success
      assert_select "img.signin-logo[src*='logo.png']"
    end
  end

  test "sign-in falls back to the GatherPack logo" do
    with_skin do
      get new_user_session_path
      assert_select "img.signin-logo[src*='logo']"
    end
  end

  test "other devise pages get the new layout and hide their old heading" do
    with_skin do
      get new_user_password_path
      assert_response :success
      assert_select ".signin-column .signin-brand"
    end
    assert_match(/\.signin-column \.logoline\s*\{\s*display: none/, Rails.root.join("app/assets/builds/skin.css").read)
  end

  # -- Color mode -------------------------------------------------------------

  test "saving a mode" do
    with_skin do
      sign_in @member

      patch color_mode_path, params: { color_mode: "dark" }, as: :json
      assert_response :no_content
      assert_equal "dark", @member.reload.color_mode

      patch color_mode_path, params: { color_mode: "light" }, as: :json
      assert_equal "light", @member.reload.color_mode

      patch color_mode_path, params: { color_mode: "auto" }, as: :json
      assert_nil @member.reload.color_mode
    end
  end

  test "an unknown mode is refused" do
    with_skin do
      sign_in @member
      patch color_mode_path, params: { color_mode: "neon" }, as: :json
      assert_response :unprocessable_entity
      assert_nil @member.reload.color_mode
    end
  end

  test "saving needs a signed-in user" do
    with_skin do
      patch color_mode_path, params: { color_mode: "dark" }, as: :json
      assert_response :redirect
    end
  end

  test "saving isn't available while the skin is off" do
    sign_in @member
    patch color_mode_path, params: { color_mode: "dark" }, as: :json
    assert_response :not_found
    assert_nil @member.reload.color_mode
  end

  test "another user's mode can't be changed" do
    with_skin do
      sign_in @member
      patch color_mode_path, params: { color_mode: "dark", user_id: @admin.id, id: @admin.id }, as: :json
      assert_response :no_content
      assert_nil @admin.reload.color_mode
      assert_equal "dark", @member.reload.color_mode
    end
  end

  test "saving adds no audit row and fires no hook" do
    hook = Hook.create!(name: "Watch users", event: "users - update", code: "raise 'hook fired'")

    with_skin do
      sign_in @member
      assert_no_difference -> { AuditLog.count } do
        patch color_mode_path, params: { color_mode: "dark" }, as: :json
      end
      assert_response :no_content
    end
  ensure
    hook&.destroy
  end

  test "the page uses the saved mode" do
    @member.update_columns(color_mode: "dark")
    with_skin do
      sign_in @member
      get root_path
      assert_includes response.body, 'var saved = "dark"'
      assert_select "meta[name=gp-color-mode][content=dark]"
    end
  end

  test "signed out is Auto" do
    with_skin do
      get new_user_session_path
      assert_includes response.body, "var saved = null"
      assert_select "meta[name=gp-color-mode][content=auto]"
    end
  end

  test "impersonating keeps the admin's mode and saves to the admin" do
    @admin.update_columns(color_mode: "dark")
    @member.update_columns(color_mode: "light")

    with_skin do
      sign_in @admin
      post impersonate_person_path(@member.person)
      get root_path
      assert_includes response.body, 'var saved = "dark"'

      patch color_mode_path, params: { color_mode: "auto" }, as: :json
      assert_response :no_content
      assert_nil @admin.reload.color_mode
      assert_equal "light", @member.reload.color_mode
    end
  end

  test "the kiosk is always light" do
    @admin.update_columns(color_mode: "dark")
    with_skin do
      sign_in @admin
      get time_kiosk_path
      assert_response :success
      assert_includes response.body, 'var saved = "light"'
      assert_select "meta[name=gp-color-mode][content=light]"
    end
  end

  test "the intake kiosk layout is always light" do
    controller = Struct.new(:true_user) do
      def self._layout = "intake_kiosk"
    end.new(@member.tap { |user| user.color_mode = "dark" })

    assert_equal "light", ModernSkin.color_mode_for(controller)
  end

  test "any other layout follows the person" do
    controller = Struct.new(:true_user) do
      def self._layout = "intake_public"
    end

    assert_nil ModernSkin.color_mode_for(controller.new(nil))
    assert_equal "dark", ModernSkin.color_mode_for(controller.new(User.new(color_mode: "dark")))
    assert_nil ModernSkin.color_mode_for(controller.new(User.new(color_mode: "neon")))
  end

  # -- Calendar ---------------------------------------------------------------

  test "calendar event text is black or white under the skin" do
    team = Team.create!(name: "Pale", team_type: team_types(:one), color: "#ffffcc")
    event = Event.create!(name: "Meet", team: team, event_type: event_types(:one),
      start_time: 1.day.from_now, end_time: 2.days.from_now)
    sign_in @admin

    get "/calendar/calendar.json", params: calendar_params
    assert_equal "#6d6753", JSON.parse(response.body).find { |e| e["id"] == event.id }["textColor"]

    with_skin do
      get "/calendar/calendar.json", params: calendar_params
      assert_equal "#000", JSON.parse(response.body).find { |e| e["id"] == event.id }["textColor"]
    end
  end

  private

  def calendar_params
    { events: true, start_time: 1.week.ago.iso8601, end_time: 1.week.from_now.iso8601 }
  end

  def create_user(email, admin: false, first_name:)
    user = User.create!(email: email, password: "Password1!", admin: admin)
    Person.create!(user: user, first_name: first_name, last_name: "Example")
    user
  end

  def with_skin(&block)
    with_setting(:feature_modern_skin, "true", &block)
  end

  def assert_skin_loaded
    assert_match %r{<link[^>]*skin-?[^>]*\.css}, response.body
    assert_includes response.body, "data-bs-theme"
  end

  def assert_no_skin
    assert_no_match %r{<link[^>]*/skin-?[^>]*\.css}, response.body
    assert_no_match "data-bs-theme", response.body
    assert_no_match "prefers-color-scheme", response.body
    assert_no_match "gp-color-mode", response.body
  end
end
