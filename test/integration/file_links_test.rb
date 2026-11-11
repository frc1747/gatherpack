require "test_helper"

class FileLinksTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers

  PNG = Rails.root.join("app/assets/images/default_profile.png").binread.freeze

  setup { host! "localhost" }

  test "an Active Storage link does not open for an anonymous visitor once it has expired" do
    blob = ActiveStorage::Blob.create_and_upload!(io: StringIO.new("%PDF-1.4 receipt with card digits"), filename: "receipt.pdf", content_type: "application/pdf")
    path = Rails.application.routes.url_helpers.rails_blob_path(blob, only_path: true)

    travel 400.days do
      get path
      follow_redirect! if response.redirect? && response.location.include?("/rails/active_storage/disk/")
    end

    assert_not response.successful? && response.body.include?("card digits"),
      "Anonymous GET of a receipt's blob link (#{path.first(48)}...) still returns the file 400 days later with no session"
  end

  test "a link signed before links expired no longer opens" do
    blob = ActiveStorage::Blob.create_and_upload!(io: StringIO.new("%PDF-1.4 receipt with card digits"), filename: "receipt.pdf", content_type: "application/pdf")
    # What Active Storage signed links with before: its default verifier, no expiry.
    old_signed_id = Rails.application.message_verifier("ActiveStorage").generate(blob.id, purpose: :blob_id)

    get "/rails/active_storage/blobs/redirect/#{old_signed_id}/receipt.pdf"

    assert_response :not_found, "a blob link signed with no expiry before the upgrade still opens"
  end

  test "an avatar link on a page opens until it expires" do
    person = people(:one)
    person.avatar.attach(io: StringIO.new(PNG), filename: "avatar.png")
    sign_in users(:one)

    get person_path(person)
    assert_response :success
    link = response.body[%r{/rails/active_storage/[^"]+avatar\.(png|jpg)}] or flunk "no avatar link on the page"
    sign_out users(:one)

    get link
    assert_response :redirect, "a fresh avatar link opens"

    travel 2.hours do
      get link
      assert_response :not_found, "an avatar link still opens after it expired"
    end
  end

  test "the userinfo picture is an expiring link, and only for an image" do
    person = Person.create!(user: User.create!(email: "picture@example.com", password: "Password1!"), first_name: "Pat", last_name: "Picture")
    person.avatar.attach(io: StringIO.new(PNG), filename: "avatar.png")
    app = Doorkeeper::Application.create!(name: "Wiki", redirect_uri: "https://example.com/callback", scopes: "user_read")
    token = Doorkeeper::AccessToken.create!(resource_owner_id: person.user.id, application_id: app.id, scopes: "user_read user_name", expires_in: 2.hours)

    get "/api/v1/userinfo", headers: { Authorization: "Bearer #{token.plaintext_token}" }
    picture = URI(response.parsed_body["picture"]).path

    get picture
    assert_response :redirect, "a fresh userinfo picture opens"
    travel 2.hours do
      get picture
      assert_response :not_found, "the userinfo picture link still opens after it expired"
    end

    ActiveStorage::Attachment.where(record: person).delete_all
    blob = ActiveStorage::Blob.create_and_upload!(io: StringIO.new("%PDF-1.4 not an image"), filename: "avatar.pdf")
    ActiveStorage::Attachment.create!(record: person, name: "avatar", blob: blob)
    get "/api/v1/userinfo", headers: { Authorization: "Bearer #{token.plaintext_token}" }
    assert_nil response.parsed_body["picture"], "userinfo offers a stored non-image avatar as the picture"
  end

  test "the theme icon loads on the sign-in page and in the manifest for anonymous visitors" do
    Theme.instance.pwa_icon.attach(io: StringIO.new(PNG), filename: "icon.png")

    get new_user_session_path
    assert_response :success
    icon = response.body[%r{/rails/active_storage/representations/redirect/[^"]+icon\.png}] or flunk "no icon on the sign-in page"
    get pwa_manifest_path(format: :json)
    assert_response :success
    manifest_icon = response.parsed_body["icons"].first["src"]

    [ icon, manifest_icon ].each do |link|
      get link
      follow_redirect!
      assert_response :success, link
      assert_equal "image/png", response.media_type
    end
  end
end
