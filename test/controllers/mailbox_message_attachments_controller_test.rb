require "test_helper"

class MailboxMessageAttachmentsControllerTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers

  setup do
    host! "localhost"
    @mailbox = Mailbox.create!(address: "den-a@example.com")
    MailboxAssignment.create!(mailbox: @mailbox, target: people(:one))
    @message = MailboxMessage.create!(mailbox: @mailbox, from: "leader@example.com", subject: "Minutes", body: "See attached")
    @message.attachments.attach(io: StringIO.new("minutes of the meeting"), filename: "minutes.txt", content_type: "text/plain")
    @attachment = @message.attachments.first
  end

  test "a member assigned to the mailbox downloads the attachment" do
    sign_in users(:one)

    get mailbox_mailbox_message_attachment_path(@mailbox, @message, @attachment)
    assert_response :redirect
    follow_redirect!

    assert_response :success
    assert_includes response.body, "minutes of the meeting"
  end

  test "a member not assigned to the mailbox is refused" do
    sign_in users(:two)

    get mailbox_mailbox_message_attachment_path(@mailbox, @message, @attachment)

    assert_response :not_found
  end

  test "the message shows the attachment through the app" do
    sign_in users(:one)

    get mailbox_mailbox_message_path(@mailbox, @message)

    assert_response :success
    assert_includes response.body, mailbox_mailbox_message_attachment_path(@mailbox, @message, @attachment)
  end
end
