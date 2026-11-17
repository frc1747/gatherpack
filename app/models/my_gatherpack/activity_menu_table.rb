module MyGatherpack
  # Places My activity in the menu's top group, right after Home. The core
  # assigns the whole table when its initializer runs, which can be after
  # this branch's, so the entry is merged in on every assignment.
  module ActivityMenuTable
    ENTRIES = { activity_path: { top: 5 } }.freeze

    def table=(value)
      super(ENTRIES.merge(value || {}))
    end
  end
end
