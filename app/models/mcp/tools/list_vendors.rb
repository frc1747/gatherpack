# Vendors, as Purchasing → Vendors lists them (Orders::VendorsController#index:
# policy_scope(Vendor).listed, preferred first). Everyone signed in sees them, to pick one on a
# request; the account note and part number pattern show only where VendorPolicy#account_note?
# allows (buyers and admins), as on the vendor's page. Needs the orders feature.
class Mcp::Tools::ListVendors < Mcp::Tool
  include Mcp::OrderRecords

  tool_name "list_vendors"
  description "Vendors (stores), preferred first, with website, link domains and whether each is in use. Buyers and admins " \
    "also see each one's account note and part number pattern. Use a vendor's ID as a request item's store."
  scope :read
  feature :orders
  input_schema(
    properties: {
      include_inactive: { type: "boolean", description: "Also list vendors no longer in use (default true, as the page)" },
      limit: limit_property
    }
  )
  output_schema(
    type: "object",
    properties: {
      items: {
        type: "array",
        items: {
          type: "object",
          properties: {
            id: { type: "string" }, name: { type: "string" }, website: { type: %w[string null] },
            domains: { type: "array", items: { type: "string" } }, preferred: { type: "boolean" }, active: { type: "boolean" },
            account_note: { type: %w[string null] }, part_number_pattern: { type: %w[string null] }
          },
          required: %w[id name website domains preferred active]
        }
      },
      truncated: { type: "boolean" }
    },
    required: %w[items truncated]
  )

  def call(include_inactive: true, limit: DEFAULT_LIMIT)
    vendors = ctx.policy_scope(Vendor).listed.order(:id)
    vendors = vendors.where(active: true) unless include_inactive
    list(vendors, limit: limit) { |vendor| vendor_json(vendor) }
  end

  private

  def vendor_json(vendor)
    json = {
      id: vendor.neat_id,
      name: vendor.name,
      website: vendor.website.presence,
      domains: Array(vendor.domains),
      preferred: vendor.preferred?,
      active: vendor.active?
    }
    return json unless ctx.allowed?(vendor, :account_note?)

    json.merge(account_note: vendor.account_note.presence, part_number_pattern: vendor.part_number_pattern.presence)
  end
end
