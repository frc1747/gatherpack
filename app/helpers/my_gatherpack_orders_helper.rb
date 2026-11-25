# The home page's orders to-dos. Each row comes from Orders::WaitingOn, the
# query the To approve and To buy pages and the My Orders card read, and links
# to an existing Orders page: nothing is approved or bought from Home.
module MyGatherpackOrdersHelper
  def my_gatherpack_order_items
    person = current_user.person
    return [] unless person

    Orders::WaitingOn.for(person).todos.map { |todo| my_gatherpack_order_item(todo) }
  end

  private

  def my_gatherpack_order_item(todo)
    order_request = todo.order_request
    case todo.kind
    when :approve
      order_item(todo, order_request.display_title, "#{order_request.total.format} · #{order_request.team.name}", orders_request_path(order_request), "Review", "stamp")
    when :reapprove
      order_item(todo, order_request.display_title, "Needs re-approval", orders_request_path(order_request), "Review", "stamp")
    when :update
      order_item(todo, order_request.display_title, truncate(todo.comment.to_s, length: 80), orders_request_path(order_request), "Update", "cart-shopping")
    when :buy
      order_item(todo, "#{pluralize(todo.count, "item")} to buy", todo.needed_by && "Earliest needed #{l todo.needed_by, format: :short}", to_buy_orders_purchases_path, "Open To buy", "credit-card")
    when :resolve
      order_item(todo, order_request.display_title, "Problem with a delivery", orders_request_path(order_request), "Resolve", "triangle-exclamation")
    when :receive
      order_item(todo, "#{pluralize(todo.count, "item")} to receive", nil, orders_deliveries_path(mine: 1), "Receive", "box-open")
    end
  end

  def order_item(todo, title, detail, path, action, icon)
    MyGatherpack::Item.new(title: title, detail: detail, at: todo.needed_by, path: path, action: action, icon: icon)
  end
end
