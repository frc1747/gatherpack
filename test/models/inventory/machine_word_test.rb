require "test_helper"

class Inventory::MachineWordTest < ActiveSupport::TestCase
  include SettingsTestHelper

  def words(name, plural = "")
    with_settings(inventory_machine_name: name, inventory_machine_name_plural: plural) do
      [ Inventory.machine_word, Inventory.machine_word(count: :many, capitalize: true), Inventory.machine_word(article: true) ]
    end
  end

  test "blank names say Machine" do
    assert_equal [ "machine", "Machines", "a machine" ], words("", "")
  end

  test "a blank plural is the plural of the name" do
    assert_equal [ "project", "Projects", "a project" ], words("Project")
  end

  test "the plural as set, and an before a vowel" do
    assert_equal [ "exhibit", "Exhibit pieces", "an exhibit" ], words("Exhibit", "Exhibit pieces")
  end

  test "a name starting with an acronym keeps its capitals mid-sentence" do
    assert_equal [ "CNC mill", "CNC mills", "a CNC mill" ], words("CNC mill")
  end

  test "on unless set to off" do
    with_settings(inventory_machines: "on") { assert Inventory.machines? }
    with_settings(inventory_machines: "") { assert Inventory.machines? }
    with_settings(inventory_machines: "Off") { assert_not Inventory.machines? }
  end
end
