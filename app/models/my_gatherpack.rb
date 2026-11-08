# A member-first set of screens, on while the feature_my_gatherpack flag is.
module MyGatherpack
  def self.enabled?
    GatherPack::Features.enabled?(:my_gatherpack)
  end
end
