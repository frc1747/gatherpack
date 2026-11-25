# Copied records carry every memo and note from the books: admins and
# architects only.
class AccountingRecordPolicy < AdminPolicy
  class Scope < ApplicationPolicy::Scope
    def resolve
      user&.admin || user&.architect ? scope.all : scope.none
    end
  end
end
