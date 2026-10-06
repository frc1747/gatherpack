# Opens draft forms whose opening time has passed and closes open forms past
# their deadline. Does nothing while forms are turned off, so a deadline that
# passes meanwhile is applied when they're turned back on.
class FormScheduleJob < ApplicationJob
  queue_as :default

  def perform
    Form.apply_schedule! if GatherPack::Features.enabled?(:forms)
  end
end
