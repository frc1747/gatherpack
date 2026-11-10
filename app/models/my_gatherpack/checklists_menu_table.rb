module MyGatherpack
  # Places Checklists in Manage for team managers. The core assigns the whole
  # table when its initializer runs, which can be after this branch's, so the
  # entry is merged in on every assignment.
  module ChecklistsMenuTable
    ENTRIES = { checklists_path: { manage: 35 } }.freeze

    def table=(value)
      super(ENTRIES.merge(value || {}))
    end
  end
end
