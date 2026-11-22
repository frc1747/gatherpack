require "test_helper"

class OauthApplicationsControllerTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers

  setup do
    host! "localhost"
    @admin = users(:one)
    @admin.update!(admin: true)
    @member = users(:two)
    @member.update!(admin: false)
    @application = OauthApplication.create!(
      name: "Scoped App",
      redirect_uri: "https://example.com/callback",
      scopes: "user_read teams_read"
    )
  end

  test "setup page shows the OAuth Applications button to an admin" do
    sign_in @admin
    get setup_path

    assert_response :success
    assert_select "a[href=?]", oauth_applications_path, text: "OAuth Applications"
  end

  test "setup page hides the OAuth Applications button from a member" do
    sign_in @member
    get setup_path

    assert_response :success
    assert_select "a[href=?]", oauth_applications_path, count: 0
  end

  test "the setup item shows exactly when the policy allows the index" do
    assert OauthApplicationPolicy.new(@admin, OauthApplication).index?
    assert_not OauthApplicationPolicy.new(@member, OauthApplication).index?
  end

  test "setup page hides the OAuth Applications button when the feature is off" do
    sign_in @admin

    with_oauth_provider_feature("false") do
      get setup_path

      assert_response :success
      assert_select "a[href=?]", oauth_applications_path, count: 0
    end
  end

  test "the setup item stays hidden when the feature was off at boot and has no routes" do
    item = GatherPack::Features.all.find { |feature| feature.key == :oauth_provider }.setup_items.first

    assert_not item.policy_check.call(Object.new)
  end

  test "index links that leave the results frame target the top frame" do
    sign_in @admin
    get oauth_applications_path

    assert_response :success
    assert_select "turbo-frame#results" do
      assert_select "a[href=?][data-turbo-frame=_top]", oauth_application_path(@application), text: "Scoped App"
      assert_select "a[href=?][data-turbo-frame=_top]", edit_oauth_application_path(@application), text: "Edit"
      assert_select "a[href=?][data-turbo-method=delete][data-turbo-frame=_top]", oauth_application_path(@application), text: "Delete"
    end
  end

  test "index links still target the top frame in a search response for the frame" do
    sign_in @admin
    get oauth_applications_path, params: { q: { name_cont: "Scoped" } }, headers: { "Turbo-Frame" => "results" }

    assert_response :success
    assert_select "turbo-frame#results a[data-turbo-frame=_top]", text: "Scoped App"
  end

  test "the sort links in the results frame work" do
    sign_in @admin

    [ "name asc", "updated_at desc" ].each do |sort|
      get oauth_applications_path, params: { q: { s: sort } }, headers: { "Turbo-Frame" => "results" }

      assert_response :success
      assert_select "turbo-frame#results a[data-turbo-frame=_top]", text: "Scoped App"
    end
  end

  test "deleting from the index removes the application" do
    sign_in @admin

    assert_difference -> { OauthApplication.count }, -1 do
      delete oauth_application_path(@application)
    end
    assert_redirected_to oauth_applications_url
  end

  test "show offers a copy button for the secret without repeating it in an attribute" do
    sign_in @admin
    post oauth_applications_path, params: { oauth_application: { name: "New App", redirect_uri: "https://example.com/new", selected_scopes: [ "", "user_read" ] } }
    secret = flash[:client_secret]
    assert_predicate secret, :present?
    follow_redirect!

    assert_response :success
    assert_equal 1, response.body.scan(secret).size
    assert_select ".alert", text: /successfully created/
    assert_select "[data-controller=clipboard]", count: 2
    assert_select "[data-clipboard-target=source]", text: secret
    assert_select "button[type=button][data-action='clipboard#copy'][aria-label='Copy Client Secret']", text: "Copy"
    assert_select "[data-clipboard-text-value]", count: 0
    assert_select "button[value=?]", secret, count: 0
  end

  test "the page isn't cached by Turbo while the secret is on it" do
    sign_in @admin
    post oauth_applications_path, params: { oauth_application: { name: "New App", redirect_uri: "https://example.com/new", selected_scopes: [ "", "user_read" ] } }
    follow_redirect!

    assert_select "head meta[name=turbo-cache-control][content=no-cache]"

    get response.request.path
    assert_response :success
    assert_select "meta[name=turbo-cache-control]", count: 0
  end

  test "show offers a copy button for the client id and no secret after the first view" do
    sign_in @admin
    get oauth_application_path(@application)

    assert_response :success
    assert_select "[data-clipboard-target=source]", text: @application.uid, count: 1
    assert_select "button[aria-label='Copy Client ID']", text: "Copy"
    assert_select "button[aria-label='Copy Client Secret']", count: 0
  end

  test "the form explains that several redirect URIs are allowed" do
    sign_in @admin
    get edit_oauth_application_path(@application)

    assert_response :success
    assert_select ".oauth_application_redirect_uri", text: /Separate them with a space or a new line/
  end

  test "creating an application with no scopes is refused" do
    sign_in @admin

    assert_no_difference -> { OauthApplication.count } do
      post oauth_applications_path, params: { oauth_application: { name: "No Scopes", redirect_uri: "https://example.com/new", selected_scopes: [ "" ] } }
    end

    assert_response :unprocessable_entity
    assert_select ".oauth_application_selected_scopes .invalid-feedback", text: "Choose at least one scope."
  end

  test "unticking every scope on edit is refused and leaves the stored scopes alone" do
    sign_in @admin

    patch oauth_application_path(@application), params: { oauth_application: { name: "Renamed", selected_scopes: [ "" ] } }

    assert_response :unprocessable_entity
    assert_select ".oauth_application_selected_scopes .invalid-feedback", text: "Choose at least one scope."
    @application.reload
    assert_equal "Scoped App", @application.name
    assert_equal %w[user_read teams_read], @application.scopes.to_a
  end

  test "an application already without scopes must choose some when edited" do
    @application.update_columns(scopes: "")
    sign_in @admin

    patch oauth_application_path(@application), params: { oauth_application: { name: "Renamed", selected_scopes: [ "" ] } }
    assert_response :unprocessable_entity
    assert_equal "Scoped App", @application.reload.name

    patch oauth_application_path(@application), params: { oauth_application: { name: "Renamed", selected_scopes: [ "", "user_read" ] } }
    assert_redirected_to oauth_application_path(@application)
    assert_equal %w[user_read], @application.reload.scopes.to_a
  end

  test "the edit page ticks a stored scope that is no longer configured" do
    @application.update!(scopes: "user_read legacy_scope")
    sign_in @admin
    get edit_oauth_application_path(@application)

    assert_response :success
    assert_select "input[type=checkbox][value=user_read][checked]"
    assert_select "input[type=checkbox][value=legacy_scope][checked]"
    assert_select "input[type=checkbox][value=teams_read]:not([checked])"
  end

  test "saving unchanged keeps stored scopes that are no longer configured" do
    [ "user_read legacy_scope", "legacy_only" ].each do |stored|
      @application.update!(scopes: stored)
      sign_in @admin
      get edit_oauth_application_path(@application)
      ticked = css_select("input[type=checkbox][name='oauth_application[selected_scopes][]'][checked]").map { |box| box["value"] }

      patch oauth_application_path(@application), params: { oauth_application: { name: "Renamed", selected_scopes: [ "" ] + ticked } }

      assert_redirected_to oauth_application_path(@application)
      assert_equal stored.split.sort, @application.reload.scopes.to_a.sort
    end
  end

  test "a stored scope that is no longer configured can be unticked" do
    @application.update!(scopes: "user_read legacy_scope")
    sign_in @admin

    patch oauth_application_path(@application), params: { oauth_application: { name: "Scoped App", selected_scopes: [ "", "user_read" ] } }

    assert_equal %w[user_read], @application.reload.scopes.to_a
  end

  test "conditions on columns that aren't allowlisted are ignored" do
    sign_in @admin

    { secret_start: "no-such-secret", uid_cont: "no-such-uid", redirect_uri_cont: "no-such-uri" }.each do |condition, value|
      get oauth_applications_path, params: { q: { condition => value } }

      assert_response :success
      assert_select "a[href=?]", oauth_application_path(@application), text: "Scoped App"
    end
  end

  test "the edit page ticks the scopes the application has" do
    sign_in @admin
    get edit_oauth_application_path(@application)

    assert_response :success
    assert_select "input[type=checkbox][value=user_read][checked]"
    assert_select "input[type=checkbox][value=teams_read][checked]"
    assert_select "input[type=checkbox][value=badges_read][checked]", count: 0
  end

  test "resubmitting the edit form with only the name changed keeps the scopes" do
    sign_in @admin
    get edit_oauth_application_path(@application)
    ticked = css_select("input[type=checkbox][name='oauth_application[selected_scopes][]'][checked]").map { |box| box["value"] }

    patch oauth_application_path(@application), params: { oauth_application: { name: "Renamed", selected_scopes: [ "" ] + ticked } }

    assert_redirected_to oauth_application_path(@application)
    @application.reload
    assert_equal "Renamed", @application.name
    assert_equal %w[user_read teams_read], @application.scopes.to_a
  end

  private

  # Sets the flag in a throwaway copy of the settings file: parallel test
  # workers share the real one, and settings that read the file would see
  # another worker's value. Covers settings that keep their value in the
  # process too.
  def with_oauth_provider_feature(value)
    settings = Settings.instance
    original_store = settings.store
    original_value = Settings.get(:feature_oauth_provider).instance_variable_get(:@value)
    path = Rails.root.join("tmp", "test-settings-#{Process.pid}-#{SecureRandom.hex(4)}.pstore").to_s
    current = original_store.transaction(true) { original_store.roots.to_h { |key| [ key, original_store[key] ] } }
    settings.store = PStore.new(path, true)
    settings.store.transaction { current.each { |key, stored| settings.store[key] = stored } }
    Settings[:feature_oauth_provider] = value
    yield
  ensure
    Settings.get(:feature_oauth_provider).instance_variable_set(:@value, original_value)
    settings.store = original_store
    FileUtils.rm_f(path)
  end
end
