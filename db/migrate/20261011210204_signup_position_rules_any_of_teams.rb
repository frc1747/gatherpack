# A position keeps at most one rule of each kind, and a team rule holds any
# of several teams. Existing rules are folded together: badge and team rules
# of the same kind on one position merge into one rule with the union of
# their badges or teams; for age rules the first one made is kept.
class SignupPositionRulesAnyOfTeams < ActiveRecord::Migration[8.1]
  BADGE = 0
  AGE = 1
  TEAM = 2

  def up
    add_column :signup_position_rules, :team_ids, :uuid, array: true, null: false, default: []
    execute "UPDATE signup_position_rules SET team_ids = ARRAY[team_id] WHERE team_id IS NOT NULL"

    merge_duplicates(BADGE, :badge_ids)
    merge_duplicates(TEAM, :team_ids)
    trim_duplicate_ages

    remove_reference :signup_position_rules, :team, type: :uuid, foreign_key: true, index: true
  end

  # Merged rules can't be split back: each keeps only its first team.
  def down
    add_reference :signup_position_rules, :team, type: :uuid, foreign_key: true, index: true
    execute "UPDATE signup_position_rules SET team_id = team_ids[1]"
    execute <<~SQL
      UPDATE signup_position_rules SET team_id = NULL
      WHERE team_id IS NOT NULL AND NOT EXISTS (SELECT 1 FROM teams WHERE teams.id = signup_position_rules.team_id)
    SQL
    remove_column :signup_position_rules, :team_ids
  end

  private

  def duplicate_groups(kind)
    rows = select_rows(<<~SQL)
      SELECT signup_position_id, array_agg(id ORDER BY created_at, id)
      FROM signup_position_rules WHERE kind = #{kind}
      GROUP BY signup_position_id HAVING count(*) > 1
    SQL
    rows.map { |position_id, ids| [ position_id, ids.is_a?(Array) ? ids : ids.delete("{}").split(",") ] }
  end

  def merge_duplicates(kind, column)
    duplicate_groups(kind).each do |position_id, (keep, *rest)|
      ids = [ keep, *rest ].map { |id| quote(id) }.join(", ")
      execute <<~SQL
        UPDATE signup_position_rules SET #{column} = (
          SELECT coalesce(array_agg(DISTINCT value), '{}') FROM signup_position_rules, unnest(#{column}) AS value
          WHERE id IN (#{ids})
        )
        WHERE id = #{quote(keep)}
      SQL
      execute "DELETE FROM signup_position_rules WHERE id IN (#{rest.map { |id| quote(id) }.join(", ")})"
      say "Merged #{rest.size + 1} #{column == :team_ids ? "team" : "badge"} rules on position #{position_id}"
    end
  end

  def trim_duplicate_ages
    duplicate_groups(AGE).each do |position_id, (_keep, *rest)|
      rest.each do |id|
        min_age, max_age = select_rows("SELECT min_age, max_age FROM signup_position_rules WHERE id = #{quote(id)}").first
        execute "DELETE FROM signup_position_rules WHERE id = #{quote(id)}"
        say "Removed extra age rule #{id} (min #{min_age.inspect}, max #{max_age.inspect}) on position #{position_id}"
      end
    end
  end
end
