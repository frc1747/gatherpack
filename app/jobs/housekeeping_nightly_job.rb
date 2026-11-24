# Nightly: archives what each registered type's "Archive automatically"
# setting says is due (Housekeeping.run). Every setting is blank by default,
# so this does nothing until someone sets one. Purges never run here.
class HousekeepingNightlyJob < ApplicationJob
  queue_as :default

  def perform
    Housekeeping.run
  end
end
