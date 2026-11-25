# Builders for the screen kit's shared partials (app/views/shared/_page_header,
# _state_line, _action_row and the rest).
module ScreenKitHelper
  # One action for shared/_action_row or a filter bar's table actions.
  # style: a Bootstrap button colour (:warning for Edit, :primary for the
  # page's job). visible: false leaves it out (pass the policy check).
  # lifecycle: true (Archive, Restore) puts it in More, after the ordinary
  # actions; destructive: true (Delete) puts it last, in red. more: true puts
  # an ordinary action in More even when there's room for it as a button.
  # data: attributes for the rendered link or button. A nil path with data
  # renders a plain <button type="button"> for page script, such as Print
  # with data: { action: "form-results#print" }.
  def screen_action(label, path, style: :secondary, method: :get, confirm: nil, visible: true, lifecycle: false, destructive: false, more: false, data: {})
    ScreenKit::Action.new(label:, path:, style:, http_method: method, confirm:, visible:, lifecycle:, destructive:, more:, data:)
  end

  # The current state in words, with an optional link to where it's set.
  def state_line(text, link_text: nil, link_path: nil)
    render "shared/state_line", text:, link_text:, link_path:
  end

  # An action as a full-size button: a link, or button_to for POST/DELETE.
  # outer: classes for the outermost element (the link, or button_to's form),
  # such as "d-none d-md-block" to hide it at phone width.
  def screen_action_button(action, style: nil, outer: nil)
    screen_action_tag(action, "btn btn-#{style || action.style}", outer)
  end

  # An action as an item in a dropdown menu; destructive items are red.
  def screen_action_item(action)
    screen_action_tag(action, [ "dropdown-item", ("text-danger" if action.destructive?) ].compact.join(" "))
  end

  # url with options merged into its query: the query it already has, then
  # the page's options, then the given ones. Blank values are dropped.
  def screen_filter_url(url, options = {}, **overrides)
    uri = URI.parse(url_for(url))
    query = Rack::Utils.parse_nested_query(uri.query)
      .merge(options.to_h.stringify_keys)
      .merge(overrides.stringify_keys)
      .compact_blank
    uri.query = query.to_query.presence
    uri.to_s
  end

  # Data attributes that give a table's wrapper a Columns chooser,
  # remembered per viewer under key, and sorting and filtering by its
  # headings (table-filter; data-table-filter="off" inside turns that off):
  # tag.div(class: "table-responsive", data: column_chooser_data("orders-report")).
  # On a wrapper that also holds a filter bar, the chooser goes in the bar's
  # table actions. data: the wrapper's other data attributes; a controller
  # there is kept. A table action built with data: { table_filter_carry: true }
  # sends the heading filters and sort along; TableFilterParams applies them.
  def column_chooser_data(key, **data)
    data.merge(controller: [ data[:controller], "column-chooser table-filter" ].compact.join(" "), column_chooser_key_value: key)
  end

  private

  def screen_action_tag(action, classes, outer = nil)
    if action.script?
      button_tag action.label, type: "button", class: [ classes, outer ].compact.join(" "), data: action.data
    elsif action.get?
      link_to action.label, action.path, class: [ classes, outer ].compact.join(" "), data: action.data.merge(turbo_confirm: action.confirm).compact
    else
      button_to action.label, action.path, method: action.http_method, class: classes, data: action.data,
        form: { class: [ "button_to", outer ].compact.join(" "), data: { turbo_confirm: action.confirm }.compact }
    end
  end
end
