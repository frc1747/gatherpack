require "test_helper"
require_relative "../support/checklist_reminders_world"

class ChecklistEmailLevelTest < ActiveSupport::TestCase
  include ChecklistRemindersWorld

  setup do
    build_checklists_world
    @checklist = create_world_checklist
  end

  test "a field kept out of email holds its item at Just sign in whatever the item and checklist say" do
    with_reminders do
      grades = create_field("Grade Point Average", :integer, keep_out_of_email: true)
      item = add_item(@checklist, :person_field, "Passing all classes", { field_id: grades.id, operator: "at_least", number: 2 }, email_level: "everything")

      assert_equal "sign_in", Checklists::EmailLevel.for(item)
      assert_equal "Email: just \"sign in\", because it reads Grade Point Average, which is kept out of email", Checklists::EmailLevel.note(item)

      grades.update!(keep_out_of_email: false)
      assert_equal "everything", Checklists::EmailLevel.for(item.reload)
      assert_equal "Email: everything", Checklists::EmailLevel.note(item)
    end
  end

  test "the checklist's level caps an item set to Everything" do
    with_reminders do
      @checklist.update!(email_level: "name_only")
      item = add_item(@checklist, :badge, "Safety", { badge_ids: [ @safety.id ] }, email_level: "everything")

      assert_equal "name_only", Checklists::EmailLevel.for(item)
      assert_equal "Email: name only, because the checklist allows no more", Checklists::EmailLevel.note(item)
    end
  end

  test "an item can lower the checklist's level, not raise it" do
    with_reminders do
      lowered = add_item(@checklist, :badge, "Safety", { badge_ids: [ @safety.id ] }, email_level: "sign_in")
      same = add_item(@checklist, :has_login, "Login")

      assert_equal "sign_in", Checklists::EmailLevel.for(lowered)
      assert_equal "Email: just \"sign in\", because it's set on this item", Checklists::EmailLevel.note(lowered)
      assert_equal "everything", Checklists::EmailLevel.for(same)

      @checklist.update!(email_level: "sign_in")
      raised = add_item(@checklist, :has_login, "Login again", {}, email_level: "name_only")
      assert_equal "sign_in", Checklists::EmailLevel.for(raised)
    end
  end

  test "a group with one kept-out field item is held at Just sign in, and so are its items" do
    with_reminders do
      grades = create_field("Grade Point Average", :integer, keep_out_of_email: true)
      group = add_item(@checklist, :any_of, "Eligible")
      add_item(@checklist, :badge, "Safety", { badge_ids: [ @safety.id ] }, parent: group)
      add_item(@checklist, :person_field, "Grades", { field_id: grades.id, operator: "at_least", number: 2 }, parent: group)

      assert_equal "sign_in", Checklists::EmailLevel.for(group.reload)
      assert_match "it holds Grades", Checklists::EmailLevel.note(group)
    end
  end

  test "a group set lower holds the items inside it" do
    with_reminders do
      group = add_item(@checklist, :any_of, "Either", {}, email_level: "name_only")
      child = add_item(@checklist, :has_login, "Login", {}, parent: group)

      assert_equal "name_only", Checklists::EmailLevel.for(child)
      assert_match "it's set on the group Either", Checklists::EmailLevel.note(child)
    end
  end

  test "a group's note names the real cause: the checklist, or the level set on the group" do
    with_reminders do
      group = add_item(@checklist, :any_of, "Kit")
      add_item(@checklist, :has_login, "Shirt size", {}, parent: group)
      add_item(@checklist, :badge, "Safety", { badge_ids: [ @safety.id ] }, parent: group)

      @checklist.update!(email_level: "name_only")
      assert_equal "Email: name only, because the checklist allows no more", Checklists::EmailLevel.note(group.reload)

      @checklist.update!(email_level: "everything")
      group.update!(email_level: "name_only")
      assert_equal "Email: name only, because it's set on this item", Checklists::EmailLevel.note(group.reload)

      group.update!(email_level: nil)
      group.children.find_by!(label: "Safety").update!(email_level: "name_only")
      assert_equal "Email: name only, because it holds Safety (name only)", Checklists::EmailLevel.note(group.reload)
    end
  end

  test "an item showing another checklist says no more than that checklist's reminders" do
    with_reminders do
      other = create_world_checklist("Academic", email_level: "sign_in")
      add_item(other, :has_login, "Login")
      item = add_item(@checklist, :checklist, "Academic done", { checklist_id: other.id })

      assert_equal "sign_in", Checklists::EmailLevel.for(item)
      assert_match "it shows Academic", Checklists::EmailLevel.note(item)
    end
  end

  test "levels are validated and blank on an item means the checklist's" do
    with_reminders do
      @checklist.email_level = "loud"
      assert_not @checklist.valid?

      item = add_item(@checklist, :has_login, "Login", {}, email_level: "")
      assert_nil item.email_level
      item.email_level = "loud"
      assert_not item.valid?
    end
  end

  test "level labels come from settings" do
    with_reminders(checklists_email_level_sign_in_label: "Sign in only") do
      assert_equal "Sign in only", Checklists::EmailLevel.label("sign_in")
      assert_equal "Everything", Checklists::EmailLevel.label("everything")
    end
  end
end
