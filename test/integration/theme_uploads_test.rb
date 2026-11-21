require "test_helper"

class ThemeUploadsTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers

  PDF = "%PDF-1.4 not an image\n".freeze

  setup do
    host! "localhost"
    @admin = User.create!(email: "theme-admin@example.com", password: "Password1!", admin: true)
    Person.create!(user: @admin, first_name: "Ada", last_name: "Admin")
  end

  test "a refused logo shows the form again with the reason" do
    sign_in @admin
    svg = Rack::Test::UploadedFile.new(StringIO.new(%(<svg xmlns="http://www.w3.org/2000/svg"></svg>)), "image/svg+xml", original_filename: "logo.svg")

    patch theme_path, params: { theme: { logo: svg } }

    assert_response :unprocessable_entity
    assert_includes response.body, "must be a PNG, JPEG or WEBP file"
    assert_not Theme.instance.logo.attached?
  end

  test "a refused PWA icon shows the form again with the reason" do
    sign_in @admin
    icon = Rack::Test::UploadedFile.new(StringIO.new(PDF), "image/png", original_filename: "icon.png")

    patch theme_path, params: { theme: { pwa_icon: icon } }

    assert_response :unprocessable_entity
    assert_includes response.body, "must be a PNG, JPEG or WEBP file"
    assert_not Theme.instance.pwa_icon.attached?
  end

  test "a non-image PWA icon stored earlier does not break the sign-in page or the manifest" do
    blob = ActiveStorage::Blob.create_and_upload!(io: StringIO.new(PDF), filename: "icon.pdf")
    ActiveStorage::Attachment.create!(record: Theme.instance, name: "pwa_icon", blob: blob)

    get new_user_session_path
    assert_response :success, "a stored non-image PWA icon breaks the sign-in page"

    get pwa_manifest_path(format: :json)
    assert_response :success, "a stored non-image PWA icon breaks the manifest"
    assert_equal "/android-chrome-192x192.png", response.parsed_body["icons"].first["src"]
  end
end
