# An optional challenge on the public sign-up form. None is installed by
# default; an adapter (a separate feature) registers itself with
#
#   Intake::BotCheck.adapter = MyAdapter.new
#
# An adapter responds to name, partial (rendered in the form, or nil) and
# passed?(params, request); it may also respond to failure_message, shown when
# passed? is false (without one the submission is dropped quietly). The honeypot
# and minimum time (FormGuard) always run, whatever the adapter.
module Intake::BotCheck
  class None
    def name
      nil
    end

    def partial
      nil
    end

    def passed?(_params, _request)
      true
    end
  end

  mattr_writer :adapter

  def self.adapter
    @@adapter ||= None.new
  end

  def self.installed?
    !adapter.is_a?(None)
  end
end
