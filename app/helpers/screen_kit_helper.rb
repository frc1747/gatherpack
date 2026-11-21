# Builders for the screen kit's shared partials (app/views/shared/_page_header,
# _state_line, _action_row and the rest).
module ScreenKitHelper
  # One action for shared/_action_row or a filter bar's table actions.
  # style: a Bootstrap button colour (:warning for Edit, :primary for the
  # page's job). visible: false leaves it out (pass the policy check).
  # lifecycle: true (Archive, Restore) puts it after the ordinary actions;
  # destructive: true (Delete) puts it last, in red.
  def screen_action(label, path, style: :secondary, method: :get, confirm: nil, visible: true, lifecycle: false, destructive: false)
    ScreenKit::Action.new(label:, path:, style:, http_method: method, confirm:, visible:, lifecycle:, destructive:)
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

  private

  def screen_action_tag(action, classes, outer = nil)
    if action.get?
      link_to action.label, action.path, class: [ classes, outer ].compact.join(" "), data: { turbo_confirm: action.confirm }.compact
    else
      button_to action.label, action.path, method: action.http_method, class: classes,
        form: { class: [ "button_to", outer ].compact.join(" "), data: { turbo_confirm: action.confirm }.compact }
    end
  end
end
