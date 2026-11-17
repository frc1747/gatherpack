# Emails about order requests, sent like the other GatherPack notices: one
# SendEmailJob per recipient through the email gateway, so no one sees
# anyone else's address, and nothing is sent (but nothing fails) when no
# gateway is set up. Nothing is sent while Orders is turned off.
#
# Each notice in spec §3.11 has one public method here, so a connector (push,
# chat) can prepend onto it and reach the same people. They're called from
# Orders::EventNotices, which the request's timeline entries and status
# changes drive, and from the jobs in Orders::Reminders. The person who made
# a change (by:) isn't told about their own action. Every method returns the
# number of people it went to.
class OrderNotices
  include ERB::Util

  # Submitted or resubmitted: the approvers on the step it waits at.
  def submitted(order_request, by: nil)
    deliver(approvers_now(order_request), "To approve: #{order_request.display_title}", by: by) do
      "<p>#{h(order_request.requested_by.display_name)} asked for #{h(summary(order_request))} " \
        "for #{h(order_request.team.name)}#{h(needed_by_text(order_request))}. It's waiting for your decision.</p>#{details(order_request)}"
    end
  end

  # Approved on a step that isn't the last: the approvers on the next step.
  def step_approved(order_request, by: nil)
    deliver(approvers_now(order_request), "To approve: #{order_request.display_title}", by: by) do
      "<p>#{h(by&.display_name || "An approver")} approved #{h(order_request.display_title)} for " \
        "#{h(order_request.team.name)}. It's now waiting for your decision.</p>#{details(order_request)}"
    end
  end

  # Final approval: the requester and watchers now, and each buyer who asked
  # to hear about every approval (the rest get Orders::Reminders' digest).
  # A re-approval (a buyer's change that went past the tolerance) is told to
  # the requester alone: nothing is left to buy.
  def approved(order_request, by: nil, reapproval: false)
    if reapproval
      return deliver([ order_request.requested_by ], "Approved: #{order_request.display_title}", by: by) do
        "<p>The higher price on #{h(order_request.display_title)} was approved.</p>#{details(order_request)}"
      end
    end

    told = deliver(Orders::Recipients.requester_and_watchers(order_request), "Approved: #{order_request.display_title}", by: by) do
      "<p>#{h(order_request.display_title)} was approved. A buyer will order it.</p>#{details(order_request)}"
    end
    buyers = Orders::Recipients.buyers(order_request.team_id).select { |person| OrderNoticePreference.for(person).buyer_immediate? }
    told + deliver(buyers, "To buy: #{order_request.display_title}", by: by) do
      "<p>#{h(order_request.display_title)} for #{h(order_request.team.name)} was approved and is ready to buy" \
        "#{h(needed_by_text(order_request))}.</p>#{details(order_request)}#{preference_link}"
    end
  end

  # Changes requested: the requester and watchers, with the comment.
  def changes_requested(order_request, comment: nil, by: nil)
    deliver(Orders::Recipients.requester_and_watchers(order_request), "Needs changes: #{order_request.display_title}", by: by) do
      "<p>#{h(by&.display_name || "An approver")} asked for changes to #{h(order_request.display_title)}.</p>" \
        "#{comment_text(comment)}<p>Change it and send it again.</p>#{details(order_request)}"
    end
  end

  # Declined: the requester and watchers, with the comment.
  def declined(order_request, comment: nil, by: nil, reapproval: false)
    people = reapproval ? [ order_request.requested_by ] : Orders::Recipients.requester_and_watchers(order_request)
    deliver(people, "Declined: #{order_request.display_title}", by: by) do
      "<p>#{h(by&.display_name || "An approver")} declined #{h(order_request.display_title)}.</p>#{comment_text(comment)}#{details(order_request)}"
    end
  end

  # Items of the request were ordered on one purchase: the requester and
  # watchers.
  def ordered(order_request, purchase, by: nil)
    lines = order_request.order_lines.select { |line| line.purchase_id == purchase.id }
    deliver(Orders::Recipients.requester_and_watchers(order_request), "Ordered: #{order_request.display_title}", by: by) do
      "<p>#{h(list(lines))} #{lines.size == 1 ? 'was' : 'were'} ordered from #{h(purchase.vendor_name)}" \
        "#{h(expected_text(purchase.expected_on))}.</p>#{details(order_request)}"
    end
  end

  # One item is delayed, with its expected date when the buyer gave one.
  def backordered(order_line, by: nil)
    order_request = order_line.order_request
    deliver(Orders::Recipients.requester_and_watchers(order_request), "Delayed: #{order_line.display_name}", by: by) do
      "<p>#{h(order_line.display_name)} on #{h(order_request.display_title)} is delayed" \
        "#{h(expected_text(order_line.expected_on))}.</p>#{details(order_request)}"
    end
  end

  # Received in full: the requester, watchers and the buyers of its
  # purchases.
  def received(order_request, by: nil)
    buyers = order_request.order_lines.filter_map { |line| line.purchase&.buyer }
    deliver(Orders::Recipients.requester_and_watchers(order_request) + buyers, "Here: #{order_request.display_title}", by: by) do
      "<p>Everything on #{h(order_request.display_title)} has arrived.</p>#{details(order_request)}"
    end
  end

  # A delivery problem on an item: the buyer who ordered it.
  def problem(order_line, by: nil)
    order_request = order_line.order_request
    deliver([ order_line.purchase&.buyer ], "Problem with delivery: #{order_line.display_name}", by: by) do
      "<p>#{h(by&.display_name || "Someone")} reported a problem with #{h(order_line.display_name)} " \
        "on #{h(order_request.display_title)}. Please reorder it or cancel it.</p>#{details(order_request)}"
    end
  end

  # A buyer's change raised the total past the tolerance: the final step's
  # approvers.
  def needs_reapproval(order_request, by: nil)
    deliver(Orders::Recipients.approvers(order_request, order_request.final_step), "Approve again: #{order_request.display_title}", by: by) do
      lines = order_request.reapproval_lines
      "<p>The price of #{h(list(lines))} on #{h(order_request.display_title)} went up. It needs your approval again.</p>#{details(order_request)}"
    end
  end

  # Needed within 3 days with nothing ordered: whoever holds it, the
  # approvers while it's undecided, the buyers once approved.
  def needed_soon(order_request)
    holders = order_request.submitted? ? approvers_now(order_request) : Orders::Recipients.buyers(order_request.team_id)
    deliver(holders, "Needed soon: #{order_request.display_title}") do
      "<p>#{h(order_request.display_title)} is needed by #{h(order_request.needed_by.strftime("%a %b %-d"))} and nothing is " \
        "ordered yet.</p>#{details(order_request)}"
    end
  end

  # Submitted and undecided for 5 days: the approvers on its current step.
  def undecided(order_request)
    deliver(approvers_now(order_request), "Still waiting: #{order_request.display_title}") do
      "<p>#{h(order_request.display_title)} has been waiting for a decision since " \
        "#{h(local(order_request.submitted_at).strftime("%a %b %-d"))}.</p>#{details(order_request)}"
    end
  end

  # The daily digest for a buyer: approved requests waiting to be bought.
  def buyer_digest(person, order_requests)
    deliver([ person ], "To buy: #{order_requests.size} #{order_requests.size == 1 ? 'request' : 'requests'}") do
      rows = order_requests.map do |order_request|
        "<li>#{link_to_request(order_request)}, #{h(order_request.team.name)}#{h(needed_by_text(order_request))}</li>"
      end
      "<p>Approved and waiting for you to buy:</p><ul>#{rows.join}</ul>#{preference_link}"
    end
  end

  private

  # Sends one email per person with an address and returns how many. The
  # block gives the body. The person named by by: isn't included.
  def deliver(people, subject, by: nil)
    return 0 unless Orders.enabled?

    people = people.compact.uniq.reject { |person| person == by }.select { |person| person.user&.email.present? }
    return 0 if people.empty?

    body = yield
    gateway = Gateway[:email_sending]
    people.each do |person|
      SendEmailJob.perform_later(gateway, person.user.email, "#{Settings[:title]} - #{subject}", "<p>Hi #{h(person.first_name)},</p>#{body}")
    end
    people.size
  end

  def approvers_now(order_request)
    Orders::Recipients.approvers(order_request, order_request.current_step)
  end

  def summary(order_request)
    lines = order_request.live_lines
    lines.size == 1 ? lines.first.display_name : "#{lines.size} items (#{order_request.display_title})"
  end

  def list(lines)
    lines.map(&:display_name).to_sentence
  end

  def details(order_request)
    rows = order_request.live_lines.map { |line| "<li>#{h(line.quantity)} × #{h(line.display_name)}</li>" }
    "<ul>#{rows.join}</ul><p>Total: #{h(order_request.total.format)}. #{link_to_request(order_request, "Open the request")}</p>"
  end

  def comment_text(comment)
    comment.present? ? "<p>#{h(comment)}</p>" : ""
  end

  # Times shown in the app's time zone, as sign-up notices do.
  def local(time)
    time.in_time_zone(Settings[:time_zone].presence || "UTC")
  end

  def needed_by_text(order_request)
    order_request.needed_by ? ", needed by #{order_request.needed_by.strftime("%a %b %-d")}" : ""
  end

  def expected_text(date)
    date ? ", expected #{date.strftime("%a %b %-d")}" : ""
  end

  def preference_link
    url = Rails.application.routes.url_helpers.edit_orders_notice_preference_url
    "<p><a href=\"#{h(url)}\">Change how you hear about requests to buy</a></p>"
  end

  def link_to_request(order_request, text = nil)
    url = Rails.application.routes.url_helpers.orders_request_url(order_request)
    "<a href=\"#{h(url)}\">#{h(text || order_request.display_title)}</a>"
  end
end
