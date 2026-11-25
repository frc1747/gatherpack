# Copied records carry every memo and note from the books: admins only.
class AccountingRecordPolicy < AdminPolicy
  class Scope < ApplicationPolicy::Scope
    def resolve
      user&.admin ? scope.all : scope.none
    end
  end
end
