require "test_helper"
require "support/modern_skin_test_settings"

class ThemePaletteTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers
  include ModernSkinTestSettings

  setup do
    host! "localhost"
    @admin = create_user("admin@example.com", admin: true)
    @member = create_user("member@example.com")
    @theme = Theme.instance
    @theme.update!(brand_color: "#34b233")
  end

  # -- Flags --------------------------------------------------------------------

  test "with the flag off there's no output and the old page" do
    with_setting(:feature_modern_skin, "true") do
      sign_in @admin
      get root_path
      assert_select "style#theme-palette", false

      get edit_theme_path
      assert_response :success
      assert_select "[data-controller=theme-palette]", false
      assert_select "h2", text: "PWA Colors"
    end
  end

  test "with the flag on but the skin off there's no output and the old page" do
    with_setting(:feature_theme_palette, "true") do
      sign_in @admin
      get root_path
      assert_select "style#theme-palette", false

      get edit_theme_path
      assert_select "[data-controller=theme-palette]", false
    end
  end

  test "the preview and import are off unless the palette is on" do
    sign_in @admin

    get theme_preview_path
    assert_redirected_to edit_theme_path

    post theme_palette_import_path
    assert_redirected_to edit_theme_path
  end

  test "palette fields aren't saved with the palette off" do
    sign_in @admin
    patch theme_path, params: { theme: { brand_color: "#123456" } }

    assert_equal "#34b233", @theme.reload.brand_color
  end

  # -- Output -------------------------------------------------------------------

  test "the palette comes after the skin and before admin CSS" do
    @theme.update!(css_variables: "--x: 1;", custom_css: "body { margin: 0; }")
    with_palette do
      get new_user_session_path

      skin = response.body.index(%r{<link[^>]*skin-?[^>]*\.css})
      palette = response.body.index('id="theme-palette"')
      variables = response.body.index('id="theme-css-variables"')
      custom = response.body.index('id="theme-custom-css"')

      assert skin && palette && variables && custom
      assert_operator skin, :<, palette
      assert_operator palette, :<, variables
      assert_operator variables, :<, custom
      assert_includes response.body, "--gp-brand: #34b233"
    end
  end

  test "no picks and the flag on leaves the skin's default look" do
    @theme.update!(brand_color: nil)
    with_palette do
      get new_user_session_path

      assert_response :success
      assert_select "style#theme-palette", false
    end
  end

  test "the kiosk stays light" do
    with_palette do
      sign_in @admin
      @admin.update_columns(color_mode: "dark")
      get time_kiosk_path

      assert_select "meta[name=gp-color-mode][content=light]"
    end
  end

  # -- Theme page ---------------------------------------------------------------

  test "admins get the Colors section, Installed app colors and a closed Advanced" do
    with_palette do
      sign_in @admin
      get edit_theme_path

      assert_response :success
      assert_select "h2", text: "Colors"
      assert_select "h2", text: "Installed app colors"
      assert_select "details:not([open]) h2", text: "Advanced"
      assert_select "details textarea[name='theme[custom_css]']"
      assert_select "iframe[data-mode=light][src*='mode=light'][src*='brand_color']"
      assert_select "iframe[data-mode=dark][src*='mode=dark']"
    end
  end

  test "saving picks and clearing them" do
    with_palette do
      sign_in @admin

      patch theme_path, params: { theme: { brand_color: "#123456", background_color: "" } }
      assert_equal "#123456", @theme.reload.brand_color
      assert_nil @theme.background_color

      patch theme_path, params: { theme: { brand_color: "" } }
      assert_nil @theme.reload.brand_color
    end
  end

  test "an invalid pick is refused and shown" do
    with_palette do
      sign_in @admin
      patch theme_path, params: { theme: { brand_color: "red" } }

      assert_response :unprocessable_entity
      assert_select ".invalid-feedback", /hex color/
      assert_equal "#34b233", @theme.reload.brand_color
    end
  end

  test "warnings sit above Save without blocking it" do
    @theme.update!(brand_color: nil, text_color: "#dddddd", background_color: "#ffffff", surface_color: "#ffffff")
    with_palette do
      sign_in @admin
      get edit_theme_path

      assert_select "[data-theme-palette-target=warnings] .alert", /Page background/
      assert_operator response.body.index("data-theme-palette-target=\"warnings\""), :<, response.body.index("Save Theme")
    end
  end

  test "old variables are noted, with an offer to use them" do
    @theme.update!(css_variables: "--bs-primary: #123456;")
    with_palette do
      sign_in @admin
      get edit_theme_path

      assert_select ".alert button[form=theme-palette-import]", "Use these as my starting colors"
      assert_select "form#theme-palette-import[action=?]", theme_palette_import_path
    end
  end

  test "no offer without old variables" do
    with_palette do
      sign_in @admin
      get edit_theme_path

      assert_select "form#theme-palette-import", false
    end
  end

  # -- Import -------------------------------------------------------------------

  test "using old variables as starting colors" do
    @theme.update!(brand_color: nil, css_variables: "--bs-primary: #123456;\n--bs-body-bg: #505050;")
    with_palette do
      sign_in @admin
      post theme_palette_import_path

      assert_redirected_to edit_theme_path
      assert_equal "#123456", @theme.reload.brand_color
      assert_equal "#505050", @theme.background_color
      assert_nil @theme.css_variables
    end
  end

  test "non-admins can't import" do
    @theme.update!(css_variables: "--bs-primary: #123456;")
    with_palette do
      sign_in @member
      post theme_palette_import_path

      assert_redirected_to root_path
      assert_equal "--bs-primary: #123456;", @theme.reload.css_variables
    end
  end

  # -- Preview ------------------------------------------------------------------

  test "the preview renders real components in the requested colors and mode" do
    with_palette do
      sign_in @admin
      get theme_preview_path, params: { mode: "dark", brand_color: "#ff0000" }

      assert_response :success
      assert_select "meta[name=gp-color-mode][content=dark]"
      assert_select "style#theme-palette"
      assert_includes response.body, "--gp-brand: #ff0000"
      %w[.btn-primary .card .table trix-editor .code-editor .badge].each { |selector| assert_select selector }
    end
  end

  test "the preview saves nothing" do
    with_palette do
      sign_in @admin

      assert_no_changes -> { @theme.reload.attributes } do
        get theme_preview_path, params: { brand_color: "#ff0000", text_color: "#00ff00" }
      end
    end
  end

  test "the preview ignores bad colors" do
    with_palette do
      sign_in @admin
      get theme_preview_path, params: { brand_color: "#fff;}</style><script>alert(1)</script>" }

      assert_response :success
      assert_not_includes response.body, "<script>alert(1)"
    end
  end

  test "the preview can load in a same-origin frame" do
    with_palette do
      sign_in @admin
      get theme_preview_path

      assert_not_equal "DENY", response.headers["X-Frame-Options"]
    end
  end

  test "the preview carries warnings for the unsaved picks" do
    with_palette do
      sign_in @admin
      get theme_preview_path, params: { brand_color: "#34b233" }

      assert_includes response.body, "White text is hard to read on Brand"
    end
  end

  test "non-admins are refused the preview" do
    with_palette do
      sign_in @member
      get theme_preview_path

      assert_redirected_to root_path
    end
  end

  test "signed-out visitors are refused the preview" do
    with_palette do
      get theme_preview_path

      assert_response :redirect
      assert_not_equal theme_preview_url, response.location
    end
  end

  private

  def create_user(email, admin: false)
    user = User.create!(email: email, password: "Password1!")
    user.update_columns(admin: admin)
    Person.create!(user: user, first_name: "Test", last_name: "Person")
    user
  end

  def with_palette(&block)
    with_setting(:feature_modern_skin, "true") { with_setting(:feature_theme_palette, "true", &block) }
  end
end
