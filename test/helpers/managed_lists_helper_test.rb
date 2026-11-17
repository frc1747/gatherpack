require "test_helper"
require_relative "../support/managed_list_test_support"

class ManagedListsHelperTest < ActionView::TestCase
  include ManagedListTestSupport
  include SimpleForm::ActionViewExtensions::FormHelper

  attr_reader :current_user

  setup do
    create_managed_list_tables
    register_test_list
    @each = ManagedListTestUnit.create!(name: "Each")
    @box = ManagedListTestUnit.create!(name: "Box")
    @crate = ManagedListTestUnit.create!(name: "Crate", active: false)
    @pallet = ManagedListTestUnit.create!(name: "Pallet", active: false)
  end

  teardown do
    unregister_test_list
  end

  test "the picker offers active rows in order" do
    assert_equal [ [ "Each", @each.id ], [ "Box", @box.id ] ], managed_list_choices(GatherPack::ManagedLists.find(:test_units))
  end

  test "the picker keeps a record's retired row, marked retired" do
    html = picker_for(ManagedListTestThing.new(unit_id: @crate.id))

    assert_includes html, "Crate (retired)"
    assert_not_includes html, "Pallet"
    assert_match(/<option selected="selected" value="#{@crate.id}">/, html)
  end

  test "admins get a link to manage the list" do
    @current_user = User.new(admin: true)

    assert_includes picker_for(ManagedListTestThing.new), "Manage test units"
  end

  test "others don't get the manage link" do
    @current_user = User.new(admin: false)

    assert_not_includes picker_for(ManagedListTestThing.new), "Manage test units"
  end

  private

  def picker_for(thing)
    simple_form_for(thing, as: :thing, url: "/things") do |f|
      managed_list_select(f, :unit_id, list: :test_units)
    end
  end
end
