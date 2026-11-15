require "test_helper"

class VendorTest < ActiveSupport::TestCase
  test "a pasted link's host picks the vendor, with or without www or a subdomain" do
    vendor = Vendor.create!(name: "Parts Depot", domains: [ "PartsDepot.example" ])

    assert_equal vendor, Vendor.for_url("https://www.partsdepot.example/p/AB-1")
    assert_equal vendor, Vendor.for_url("https://shop.partsdepot.example/x")
    assert_nil Vendor.for_url("https://elsewhere.example/x")
    assert_nil Vendor.for_url("not a link")
  end

  test "an inactive vendor isn't picked from a link" do
    Vendor.create!(name: "Old Shop", domains: [ "oldshop.example" ], active: false)

    assert_nil Vendor.for_url("https://oldshop.example/item")
  end

  test "a matching part number pattern fills the part number and a non-matching one fills nothing" do
    vendor = Vendor.new(name: "Parts Depot", part_number_pattern: "/p/([A-Z0-9-]+)")

    assert_equal "AB-12", vendor.part_number_from("https://partsdepot.example/p/AB-12?ref=x")
    assert_nil vendor.part_number_from("https://partsdepot.example/search?q=gear")
    assert_nil Vendor.new(name: "No pattern").part_number_from("https://partsdepot.example/p/AB-12")
  end

  test "a pattern that isn't a regular expression is refused" do
    vendor = Vendor.new(name: "Broken", part_number_pattern: "([")

    assert_not vendor.valid?
    assert vendor.errors[:part_number_pattern].any?
  end

  test "domains are tidied from a comma or space separated list" do
    vendor = Vendor.create!(name: "Shop", domains: [ "www.Shop.example, other.example" ])

    assert_equal %w[shop.example other.example], vendor.domains
  end
end
