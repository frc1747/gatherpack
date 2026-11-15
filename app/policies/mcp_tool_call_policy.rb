class McpToolCallPolicy < AdminPolicy
  class Scope < ApplicationPolicy::Scope
    def resolve
      user&.admin ? scope.all : scope.none
    end
  end
end
