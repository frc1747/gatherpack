# Account status on the My GatherPack home page and the Family page. Lives
# here so neither feature needs the other's code. Shown while both features
# are on.
Rails.application.config.to_prepare do
  next unless defined?(MyGatherpack) && MyGatherpack.respond_to?(:register_section) && defined?(Accounting::Access)

  # Under My Season (20) and the activity section (20.5), above the widgets (25).
  MyGatherpack.register_section(:accounting, partial: "my_gatherpack/accounting", column: :side, position: 22,
    enabled: -> { GatherPack::Features.enabled?(:accounting) })

  # A ward card with only account rows isn't "Nothing to show yet".
  if defined?(FamilyHelper::Card)
    FamilyHelper::Card.prepend(MyGatherpack::AccountingFamilyCard) unless FamilyHelper::Card < MyGatherpack::AccountingFamilyCard
    FamilyHelper.prepend(MyGatherpack::AccountingFamilyCards) unless FamilyHelper < MyGatherpack::AccountingFamilyCards
  end
end
