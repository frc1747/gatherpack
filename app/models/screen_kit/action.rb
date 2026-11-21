module ScreenKit
  # One action on a screen: a button in an action row, an item in its More
  # menu, or a table action beside a filter bar. Build them with
  # ScreenKitHelper#screen_action; shared/_action_row decides where each goes.
  Action = Data.define(:label, :path, :style, :http_method, :confirm, :visible, :lifecycle, :destructive, :more, :data) do
    def initialize(label:, path:, style: :secondary, http_method: :get, confirm: nil, visible: true, lifecycle: false, destructive: false, more: false, data: {})
      super
    end

    def get?
      http_method.to_s.casecmp?("get")
    end

    # No path: a plain button for page script (data: { action: ... }).
    def script?
      path.nil?
    end

    def visible?
      visible
    end

    def lifecycle?
      lifecycle
    end

    def destructive?
      destructive
    end

    def more?
      more
    end
  end
end
