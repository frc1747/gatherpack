require_relative "commitments_world"

# The commitments fixture world (see CommitmentsWorld) with checklists
# holding count items:
#
#   Org ─ Club ─┬─ Crew: organizer (organizer badge), crew_manager
#               └─ Members: member, member2, kid
#
# organizer is "Parent of" kid. A count checklist runs on Club through
# October 2026 and covers Members.
module ChecklistsCountWorld
  include CommitmentsWorld

  def create_count_checklist(title = "Eligibility", team: @club, covers: @members, **attributes)
    checklist = Checklist.create!({ title: title, team: team, status: :active, starts_on: Date.new(2026, 10, 1),
      ends_on: Date.new(2026, 10, 31), created_by: person(:admin) }.merge(attributes))
    checklist.checklist_rules.create!(effect: :include, target_type: :team, team: covers) if covers
    checklist
  end

  def add_count_item(checklist, label = "Shifts", config = {}, **attributes)
    item = checklist.checklist_items.new({ kind: "count", label: label }.merge(attributes))
    item.config_params = { base_amount: 2, unit: "shifts" }.merge(config)
    item.save!
    item
  end

  def count_result(checklist, name, item)
    Checklists::Evaluator.new(checklist.reload).call([ person(name).id ]).dig(person(name).id, item.id)
  end

  def with_checklists(**settings, &block)
    with_settings(feature_checklists: "true", **settings, &block)
  end
end
