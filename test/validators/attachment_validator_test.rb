require "test_helper"

class AttachmentValidatorTest < ActiveSupport::TestCase
  PNG = Rails.root.join("app/assets/images/default_profile.png").binread.freeze
  PDF = "%PDF-1.4 a receipt\n".freeze

  test "an avatar must be an image" do
    person = people(:one)
    person.avatar.attach(io: StringIO.new(PDF), filename: "avatar.pdf", content_type: "application/pdf")

    assert_not person.valid?
    assert_includes person.errors[:avatar], "must be a PNG, JPEG or WEBP file"
  end

  test "the content type checked is the one identified from the file, not the declared one" do
    person = people(:one)
    person.avatar.attach(io: StringIO.new(PDF), filename: "avatar.png", content_type: "image/png")

    assert_equal "application/pdf", person.avatar.blob.content_type
    assert_not person.valid?
  end

  test "an avatar over 5 MB is refused" do
    person = people(:one)
    person.avatar.attach(io: StringIO.new(PNG + ("\0" * 5.megabytes)), filename: "avatar.png")

    assert_not person.valid?
    assert_includes person.errors[:avatar], "must be smaller than 5 MB"
  end

  test "a PNG avatar is accepted" do
    person = people(:one)
    person.avatar.attach(io: StringIO.new(PNG), filename: "avatar.png")

    assert person.valid?, person.errors.full_messages.to_sentence
    assert person.save
  end

  test "a record holding a file from before the checks can still be saved" do
    person = people(:one)
    blob = ActiveStorage::Blob.create_and_upload!(io: StringIO.new(PDF), filename: "avatar.pdf")
    ActiveStorage::Attachment.create!(record: person, name: "avatar", blob: blob)

    person.reload.first_name = "Alicia"

    assert person.save, person.errors.full_messages.to_sentence
  end

  test "receipts accept images and PDFs" do
    entry = ledger_entries(:one)
    entry.receipts.attach(io: StringIO.new(PDF), filename: "receipt.pdf")
    entry.receipts.attach(io: StringIO.new(PNG), filename: "receipt.png")

    assert entry.valid?, entry.errors.full_messages.to_sentence
    assert_equal 2, entry.reload.receipts.count
  end

  test "receipts stored before the checks can be kept while adding another" do
    entry = ledger_entries(:one)
    old = ActiveStorage::Blob.create_and_upload!(io: StringIO.new("plain text"), filename: "notes.txt")
    ActiveStorage::Attachment.create!(record: entry, name: "receipts", blob: old)

    entry.reload.receipts = [ old.signed_id, { io: StringIO.new(PNG), filename: "receipt.png" } ]

    assert entry.save, entry.errors.full_messages.to_sentence
    assert_equal 2, entry.reload.receipts.count
  end

  test "receipts refuse other types and files over 10 MB" do
    entry = ledger_entries(:one)
    entry.receipts = [
      { io: StringIO.new("<html><script>alert(1)</script></html>"), filename: "receipt.html" },
      { io: StringIO.new(PDF + ("\0" * 10.megabytes)), filename: "big.pdf" }
    ]

    assert_not entry.valid?
    assert_includes entry.errors[:receipts], "must be a PNG, JPEG, WEBP or PDF file"
    assert_includes entry.errors[:receipts], "must be smaller than 10 MB"
  end

  test "a theme logo and icon must be images" do
    theme = Theme.instance
    theme.logo.attach(io: StringIO.new(%(<svg xmlns="http://www.w3.org/2000/svg"><script>alert(1)</script></svg>)), filename: "logo.svg")
    theme.pwa_icon.attach(io: StringIO.new(PDF), filename: "icon.png")

    assert_not theme.valid?
    assert_includes theme.errors[:logo], "must be a PNG, JPEG or WEBP file"
    assert_includes theme.errors[:pwa_icon], "must be a PNG, JPEG or WEBP file"
  end
end
