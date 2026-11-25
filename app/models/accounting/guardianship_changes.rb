# Keeps ledger sources' owner links right when guardianship changes: a
# guardian who co-owns a ward's ledger isn't linked to it
# (Accounting::Ledgers::OwnerLinks), but a guardianship added, removed or
# whose type stops (or starts) being one doesn't change the ledger, so no
# ledger sync would notice. Included into Relationship and RelationshipType
# (config/initializers/accounting.rb); queues Accounting::OwnerLinksJob for
# the people involved. Does nothing while the feature is off.
module Accounting::GuardianshipChanges
  extend ActiveSupport::Concern

  included do
    after_commit :queue_accounting_owner_links
  end

  private
    def queue_accounting_owner_links
      return unless Accounting.enabled?

      Gateway::LedgerSource.queue_relink(accounting_guardianship_people)
    end

    def accounting_guardianship_people
      case self
      when Relationship
        return [] unless previously_new_record? || destroyed? || saved_change_to_relationship_type_id? ||
          saved_change_to_parent_id? || saved_change_to_child_id?

        [ parent_id, child_id, attribute_before_last_save("parent_id"), attribute_before_last_save("child_id") ].compact.uniq
      when RelationshipType
        return [] unless destroyed? || saved_change_to_guardianship?

        relationships.pluck(:parent_id, :child_id).flatten.uniq
      else []
      end
    end
end
