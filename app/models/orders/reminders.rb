# The things orders does on a schedule (spec §3.11), each called by a job in
# app/jobs/orders/. Every one does nothing while Orders is turned off, and
# the reminders go out once: OrderNoticeMark remembers them.
module Orders
  module Reminders
    NEEDED_SOON_DAYS = 3
    UNDECIDED_DAYS = 5

    module_function

    # Orders' own daily summary (Orders::Digest) for each person whose
    # choice is a summary, while Summaries isn't there to send it. Without
    # Summaries there's no Weekly Infodump to carry it, so a weekly choice
    # gets it daily too. Nothing goes to a person with nothing in it.
    def digest(now: Time.current)
      return 0 unless Orders.enabled?
      return 0 if defined?(GatherPack::Digests) && GatherPack::Digests.handles?(:orders)

      since = now - 1.day
      digest_candidates(since).count do |person|
        next false unless %i[daily weekly].include?(Orders::Config.delivery_for(person))

        OrderNotices.new.digest(person, Orders::Digest.new(person, since: since)).positive?
      end
    end

    # Needed in 3 days (or less) with nothing ordered, to whoever holds it,
    # once for each holder: the approvers, then the buyers once approved.
    def needed_soon(today: Date.current)
      return 0 unless Orders.enabled?

      OrderRequest.where(status: %i[submitted approved], needed_by: today..(today + NEEDED_SOON_DAYS)).count do |order_request|
        holder = order_request.submitted? ? "approvers" : "buyers"
        OrderNoticeMark.once(order_request, "needed_soon", "#{order_request.needed_by.iso8601}:#{holder}") { OrderNotices.new.needed_soon(order_request) }.positive?
      end
    end

    # Submitted and undecided for 5 days, to the approvers on its current
    # step. Once for each time it was submitted.
    def undecided(now: Time.current)
      return 0 unless Orders.enabled?

      OrderRequest.submitted.where(submitted_at: ..(now - UNDECIDED_DAYS.days)).count do |order_request|
        OrderNoticeMark.once(order_request, "undecided", order_request.submitted_at.to_i.to_s) { OrderNotices.new.undecided(order_request) }.positive?
      end
    end

    # Closes received requests nothing has touched for orders_close_after_days.
    def auto_close(now: Time.current)
      return 0 unless Orders.enabled?

      OrderRequest.received.where(updated_at: ..(now - Orders::Config.close_after_days.days)).count do |order_request|
        order_request.close!(by: nil)
        true
      rescue Orders::Refused
        false
      end
    end

    # Everyone who could have something in a digest: whoever may approve or
    # buy, and the people whose requests changed since `since`.
    def digest_candidates(since)
      reaches = [ Orders::Config.buyers, *Orders::Config.approval_steps.map(&:reach) ]
      changed = OrderRequest.where(id: OrderRequestEvent.where(created_at: since..).select(:order_request_id))
      people = Person.where(id: changed.select(:requested_by_id))
        .or(Person.where(id: OrderRequestWatcher.where(order_request_id: changed.select(:id)).select(:person_id)))
        .includes(:user).to_a
      (reaches.flat_map { |reach| Orders::Recipients.candidates(reach) } + people).uniq.select { |person| person.user&.email.present? }
    end

    # Approved requests with something not yet bought, within the buyer's
    # reach, the most urgent first.
    def to_buy(access)
      scope = OrderRequest.where(status: %i[approved ordering],
        id: OrderLine.where(status: :approved, purchase_id: nil).select(:order_request_id))
      scope = scope.where(team_id: access.buyer_team_ids.to_a) unless access.admin?
      scope.includes(:team).order(Arel.sql("needed_by NULLS LAST"), :submitted_at).to_a
    end
  end
end
