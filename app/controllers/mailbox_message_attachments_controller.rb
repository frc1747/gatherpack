# Mailbox attachments are linked here rather than straight to Active
# Storage, whose links open for anyone who holds them. This checks that the
# user can see the message, then redirects to a service URL that expires in
# minutes.
class MailboxMessageAttachmentsController < InternalController
  include ActiveStorage::SetCurrent

  # GET /mailboxes/1/mailbox_messages/1/attachments/1
  def show
    mailbox = authorize policy_scope(Mailbox).find(params[:mailbox_id])
    mailbox_message = authorize policy_scope(mailbox.messages).find(params[:mailbox_message_id])
    attachment = mailbox_message.attachments_attachments.find(params[:id])

    redirect_to attachment.url, allow_other_host: true
  end
end
