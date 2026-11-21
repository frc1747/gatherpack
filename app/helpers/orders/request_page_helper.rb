# The request page's header and action row (spec §3.8): the state in words,
# the one job for the viewer, and the rest in More.
module Orders
  module RequestPageHelper
    # "Robotics · Pat Doe · Needed by November 30, 2026"
    def order_request_summary(order_request)
      parts = [ order_request.team.name, order_request.requested_by.identifier_name ]
      parts << "Needed by #{l order_request.needed_by, format: :long}" if order_request.needed_by
      parts.join(" · ")
    end

    # The status words, with who it waits on or when it was ordered:
    # "Waiting for approval by Purchasing", "Ordered Nov 20: 1 of 2 here".
    def order_request_state_text(order_request)
      text = order_request_status_text(order_request)
      case order_request.status
      when "submitted"
        step = order_request.decision_step
        text = text.sub(/\AWaiting for approval/, "Waiting for approval by #{step.name}") if step
      when "ordering"
        ordered_on = order_request.order_lines.filter_map { |line| line.purchase&.ordered_on }.min
        text = text.sub(/\AOrdered/, "Ordered #{l ordered_on, format: :short}") if ordered_on
      end
      text
    end

    # The action row: the viewer's job, if any, as the one button, then More with
    # Edit, Order again, Follow and Print, and Delete draft or Cancel request
    # last.
    def order_request_actions(order_request)
      request_policy = policy(order_request)
      person = current_user.person
      job = order_request_job(order_request)
      cancellable = order_request.status.in?(%w[submitted changes_requested approved]) && order_request.order_lines.none?(&:purchase_id)
      following = person && order_request.watched_by?(person)

      [
        job,
        screen_action("Edit", edit_orders_request_path(order_request), style: :warning,
          more: true, visible: request_policy.update? && !order_request.draft? && job&.label != "Update"),
        screen_action("Order again", order_again_orders_request_path(order_request), method: :post,
          more: true, visible: !order_request.draft? && request_policy.order_again?),
        screen_action("Duplicate", duplicate_orders_request_path(order_request), method: :post,
          more: true, visible: request_policy.duplicate?),
        screen_action(following ? "Stop following" : "Follow", follow_orders_request_path(order_request),
          method: following ? :delete : :post, more: true, visible: request_policy.follow?),
        screen_action("Print", nil, more: true, data: { controller: "orders-print", action: "orders-print#print" }),
        screen_action("Delete draft", orders_request_path(order_request), method: :delete, destructive: true,
          confirm: "Delete this draft?", visible: order_request.draft? && request_policy.destroy?),
        screen_action("Cancel request", cancel_orders_request_path(order_request), method: :post, destructive: true,
          confirm: "Cancel this request? Nothing on it will be bought.", visible: cancellable && request_policy.cancel?)
      ].compact
    end

    # The one thing the viewer is here to do, or nil: finish a draft, fix
    # one sent back, buy or receive. An approver's job is the decision bar
    # on the page itself, so deciding has no button here.
    def order_request_job(order_request)
      request_policy = policy(order_request)
      person = current_user.person
      if request_policy.update? && order_request.draft?
        screen_action("Finish request", edit_orders_request_path(order_request), style: :primary)
      elsif request_policy.update? && order_request.changes_requested? && order_request.requested_by_id == person&.id
        screen_action("Update", edit_orders_request_path(order_request), style: :primary)
      elsif order_request_to_buy?(order_request)
        screen_action("Open To buy", to_buy_orders_purchases_path, style: :primary)
      elsif order_request_to_receive?(order_request)
        screen_action("Receive", orders_request_path(order_request, anchor: "receiving"), style: :primary)
      end
    end

    private

    def order_request_to_buy?(order_request)
      policy(order_request).buy? && order_request.status.in?(%w[approved ordering received]) &&
        order_request.order_lines.any? { |line| line.approved? && line.purchase_id.nil? }
    end

    def order_request_to_receive?(order_request)
      policy(order_request).receive? &&
        order_request.order_lines.any? { |line| !line.cancelled? && line.open_to_receive? && !line.problem? }
    end
  end
end
