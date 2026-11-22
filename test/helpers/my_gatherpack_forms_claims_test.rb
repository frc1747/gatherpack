require "test_helper"

class MyGatherpackFormsClaimsTest < ActionView::TestCase
  include MyGatherpackFormsHelper

  test "a form another section claims is left out of the to-do rows" do
    person = people(:one)
    entry = Struct.new(:subject, :form).new(person, Struct.new(:id, :title, :closes_at).new("f1", "Waiver", nil))
    other = Struct.new(:subject, :form).new(person, Struct.new(:id, :title, :closes_at).new("f2", "Shirt size", nil))
    stubs = { forms_to_complete: [ entry, other ], leader_todos: [] }
    MyGatherpack::Claims.register(:test, :form) { |_subject| [ "f1" ] }
    define_singleton_method(:current_user) { Struct.new(:person).new(person) }
    stubs.each { |name, value| define_singleton_method(name) { |*| value } }
    define_singleton_method(:my_gatherpack_form_entry_item) { |e, _| e.form.title }

    assert_equal [ "Shirt size" ], my_gatherpack_form_items
  ensure
    MyGatherpack::Claims.unregister(:test, :form)
  end
end
