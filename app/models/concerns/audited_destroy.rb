# PaperTrail records a destroy before the row is deleted, and audit logs live in
# their own database, so the primary rolling back a refused delete leaves behind
# an entry claiming the record is gone. Recording it after the delete isn't an
# option: PaperTrail rejects that under belongs_to_required_by_default, and it
# would save blank attributes, which breaks revert.
#
# Wrapping destroy in a versions transaction keeps the entry as it is today and
# discards it, along with those of any cascaded destroys, if the delete fails.
#
# The two databases still don't commit atomically. The primary commits first, so
# a failure before the versions commit leaves a deleted record with no entry. And
# this only covers destroy itself: if an outer transaction on the primary rolls
# back after destroy returns, the entry stays and falsely claims a delete.
module AuditedDestroy
  def destroy
    return super unless self.class.respond_to?(:paper_trail_options)

    result = false
    self.class.paper_trail.version_class.transaction(requires_new: true) do
      result = super
      raise ActiveRecord::Rollback unless result
    end
    result
  end
end
