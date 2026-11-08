# Turns Features.enabled?(:checklists) on for a block, in branches where the
# checklists feature isn't registered (and harmlessly where it is). The
# override is prepended once and switched, never replaced, so it stacks with
# other prepends on GatherPack::Features (checklists' own, for one).
module ChecklistsFlagHelper
  module Override
    class << self
      attr_accessor :on
    end

    def enabled?(key)
      (Override.on && key.to_s == "checklists") || super
    end
  end
  GatherPack::Features.singleton_class.prepend(Override)

  def with_checklists_on
    Override.on = true
    yield
  ensure
    Override.on = false
  end
end
