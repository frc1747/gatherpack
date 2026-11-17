require "test_helper"

class AuditedDestroyTest < ActiveSupport::TestCase
  class HaltedEventType < EventType
    before_destroy { throw :abort }
  end

  test "a delete refused by a foreign key writes no audit log, however often it is tried" do
    badge_type = badge_types(:one)
    assert badge_type.badges.exists?

    assert_no_difference -> { AuditLog.count } do
      2.times do
        assert_raises(ActiveRecord::InvalidForeignKey) { BadgeType.find(badge_type.id).destroy! }
      end
    end

    assert BadgeType.exists?(badge_type.id)
  end

  test "a refused delete discards the audit logs of the destroys it cascaded to" do
    person = people(:one)
    assert person.memberships.exists?
    Question.create!(person: person, team: teams(:one), title: "Refuses the delete", content: "Content")

    assert_no_difference -> { AuditLog.count } do
      assert_raises(ActiveRecord::InvalidForeignKey) { Person.find(person.id).destroy }
    end

    assert person.memberships.exists?
  end

  test "a delete halted by a callback writes no audit log and returns false" do
    event_type = HaltedEventType.find(event_types(:one).id)

    assert_no_difference -> { AuditLog.count } do
      assert_equal false, event_type.destroy
    end

    assert EventType.exists?(event_type.id)
  end

  test "a successful delete writes one audit log with the record's last state" do
    event = Event.create!(name: "Unreferenced event", start_time: 1.day.ago, event_type: event_types(:one))
    user = users(:one)

    assert_difference -> { AuditLog.where(item_id: event.id, event: "destroy").count }, 1 do
      PaperTrail.request(whodunnit: user.id) { Event.find(event.id).destroy! }
    end

    assert_not Event.exists?(event.id)
    log = AuditLog.where(item_id: event.id, event: "destroy").last
    assert_equal user.id, log.whodunnit
    assert_equal "Unreferenced event", log.reify.name
  end

  test "a delete on a model without PaperTrail is unaffected" do
    note = calendar_notes(:one)

    assert_no_difference -> { AuditLog.count } do
      assert_equal note, note.destroy
    end

    assert_not CalendarNote.exists?(note.id)
  end
end
