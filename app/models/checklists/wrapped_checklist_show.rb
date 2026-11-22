module Checklists
  # Prepended to ChecklistPolicy (config/initializers/checklists_count.rb):
  # show? asks the scope (with Checklists::WrappedChecklistScope's wrapped
  # checklist check) about this checklist alone, once per policy instance,
  # rather than resolving every checklist.
  module WrappedChecklistShow
    def show?
      return @show if defined?(@show)

      @show = ChecklistPolicy::Scope.new(user, Checklist.where(id: record.id)).resolve.exists?(id: record.id)
    end
  end
end
