require "test_helper"
require_relative "../support/checklists_world"
require Rails.root.join("db/migrate/20261108100000_remove_cutoff_on_from_checklists")

class RemoveCutoffOnFromChecklistsTest < ActiveSupport::TestCase
  include ChecklistsWorld

  setup do
    build_checklists_world
    @connection = Checklist.lease_connection
  end

  test "checklists with an end start over, so the next run stores end-of-day answers" do
    ended = create_world_checklist("Ended", ends_on: Date.new(2026, 10, 1))
    from_cutoff = create_world_checklist("From a cutoff", ends_on: nil)
    open_ended = create_world_checklist("Open", ends_on: nil)
    stamp = Time.utc(2026, 11, 7, 12)
    [ ended, from_cutoff, open_ended ].each { |checklist| checklist.update_columns(computed_at: stamp, next_refresh_at: stamp) }

    @connection.add_column :checklists, :cutoff_on, :date
    @connection.execute("UPDATE checklists SET cutoff_on = '2026-10-01' WHERE id = #{@connection.quote(from_cutoff.id)}")
    ActiveRecord::Migration.suppress_messages { RemoveCutoffOnFromChecklists.new.migrate(:up) }

    stamps = ->(checklist) { @connection.select_rows("SELECT computed_at, next_refresh_at FROM checklists WHERE id = #{@connection.quote(checklist.id)}").first }
    assert_equal [ nil, nil ], stamps[ended]
    assert_equal [ nil, nil ], stamps[from_cutoff], "its cutoff became its end"
    assert_equal 2, stamps[open_ended].compact.size, "no end: still live, left alone"
  end

  test "a cutoff moves to the end only where the end would stay valid" do
    day = ->(number) { Date.new(2026, 10, number) }
    # title => [starts_on, ends_on, cutoff_on, expected ends_on]
    cases = {
      "no end" => [ day[1], nil, day[10], day[10] ],
      "earlier than the end" => [ day[1], day[20], day[10], day[10] ],
      "later than the end" => [ day[1], day[20], day[25], day[20] ],
      "on the start" => [ day[1], nil, day[1], day[1] ],
      "no start" => [ nil, nil, day[10], day[10] ],
      "before the start, no end" => [ day[10], nil, day[1], nil ],
      "before the start, with an end" => [ day[10], day[20], day[1], day[20] ],
      "no cutoff" => [ day[1], day[20], nil, day[20] ]
    }
    ids = cases.to_h { |title, (starts_on, ends_on, _, _)| [ title, create_world_checklist(title, starts_on: starts_on, ends_on: ends_on).id ] }

    # Checklists have no such column now; put it back for the migration to
    # take away. The test's transaction undoes all of this.
    @connection.add_column :checklists, :cutoff_on, :date
    cases.each do |title, (_, _, cutoff_on, _)|
      next unless cutoff_on

      @connection.execute("UPDATE checklists SET cutoff_on = #{@connection.quote(cutoff_on)} WHERE id = #{@connection.quote(ids[title])}")
    end

    ActiveRecord::Migration.suppress_messages { RemoveCutoffOnFromChecklists.new.migrate(:up) }

    assert_not @connection.column_exists?(:checklists, :cutoff_on)
    cases.each do |title, (_, _, _, expected)|
      found = @connection.select_value("SELECT ends_on FROM checklists WHERE id = #{@connection.quote(ids[title])}")
      if expected.nil?
        assert_nil found, title
      else
        assert_equal expected, found.to_date, title
      end
    end
  end
end
