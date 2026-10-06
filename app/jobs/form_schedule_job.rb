# Opens draft forms whose opening time has passed and closes open forms past
# their deadline.
class FormScheduleJob < ApplicationJob
  queue_as :default

  def perform
    Form.apply_schedule!
  end
end
