# A retention purge someone ran (Housekeeping::Purge#run!): which one, up
# to which date, how many records went and who did it. The purged data
# isn't kept; this row and its audit entry are the trace.
class HousekeepingPurge < ApplicationRecord
  has_neat_id :hkp
  has_paper_trail versions: { class_name: "AuditLog" }

  belongs_to :person, optional: true

  validates :key, :cutoff_on, presence: true

  def purge
    Housekeeping.purges[key]
  end

  def identifier_icon
    "broom"
  end

  def identifier_name
    "#{purge&.label || key.humanize}: #{count} before #{I18n.l(cutoff_on, format: :long)}"
  end
end
