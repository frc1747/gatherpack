require "test_helper"

class AvatarUploadsTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers

  setup do
    host! "localhost"
    @admin = User.create!(email: "avatar-admin@example.com", password: "Password1!", admin: true)
    Person.create!(user: @admin, first_name: "Ada", last_name: "Admin")
    @member = people(:one)
  end

  test "a member cannot set a non-image avatar" do
    sign_in @member.user
    file = Rack::Test::UploadedFile.new(StringIO.new("%PDF-1.4 not an image\n" * 50), "application/pdf", original_filename: "avatar.pdf")

    patch person_path(@member), params: { person: { avatar: file } }

    assert_response :unprocessable_entity
    assert_not @member.reload.avatar.attached?, "a non-image avatar was stored"
  end

  test "a member cannot pass a PDF off as a PNG avatar" do
    sign_in @member.user
    file = Rack::Test::UploadedFile.new(StringIO.new("%PDF-1.4 not an image\n" * 50), "image/png", original_filename: "avatar.png")

    patch person_path(@member), params: { person: { avatar: file } }

    assert_response :unprocessable_entity
    assert_not @member.reload.avatar.attached?, "a PDF declared as image/png was stored as an avatar"
  end

  test "an avatar over 5 MB shows the form again with the reason" do
    sign_in @member.user
    png = Rails.root.join("app/assets/images/default_profile.png").binread + ("\0" * 5.megabytes)
    file = Rack::Test::UploadedFile.new(StringIO.new(png), "image/png", original_filename: "avatar.png")

    patch person_path(@member), params: { person: { avatar: file } }

    assert_response :unprocessable_entity
    assert_includes response.body, "must be smaller than 5 MB"
    assert_not @member.reload.avatar.attached?
  end

  test "a member can set a PNG avatar" do
    sign_in @member.user
    file = Rack::Test::UploadedFile.new(Rails.root.join("app/assets/images/default_profile.png"), "image/png")

    patch person_path(@member), params: { person: { avatar: file } }

    assert_redirected_to person_path(@member)
    assert_equal "image/png", @member.reload.avatar.content_type
  end

  test "a non-image avatar stored earlier does not break pages that show it" do
    blob = ActiveStorage::Blob.create_and_upload!(io: StringIO.new("%PDF-1.4 not an image\n" * 50), filename: "avatar.pdf")
    ActiveStorage::Attachment.create!(record: @member, name: "avatar", blob: blob)
    assert @member.reload.avatar.attached?

    sign_in @admin
    get people_path

    assert_response :success, "a stored non-image avatar breaks GET /people"
  end
end
