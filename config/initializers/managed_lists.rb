# Loads the managed lists registry (GatherPack::ManagedLists). Features
# register their lists in their own initializers; see the comment at the top
# of lib/gatherpack/managed_lists.rb.
require Rails.root.join("lib/gatherpack/managed_lists").to_s
