module ScreenKit
  # One action on a screen: a button in an action row, an item in its More
  # menu, or a table action beside a filter bar. Build them with
  # ScreenKitHelper#screen_action; shared/_action_row decides where each goes.
  Action = Data.define(:label, :path, :style, :http_method, :confirm, :visible, :lifecycle, :destructive) do
    def initialize(label:, path:, style: :secondary, http_method: :get, confirm: nil, visible: true, lifecycle: false, destructive: false)
      super
    end

    def get?
      http_method.to_s.casecmp?("get")
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
  end
end
