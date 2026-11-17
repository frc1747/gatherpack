require "test_helper"
require_relative "../support/checklists_world"

class ChecklistResultTest < ActiveSupport::TestCase
  include ChecklistsWorld

  setup do
    build_checklists_world
    @checklist = create_world_checklist
  end

  test "defines no generated status scopes, so not_met can't clash with met's negative scope" do
    %i[ met pending not_met exempt not_not_met previously_met previously_not_met not_previously_met ].each do |name|
      assert_not ChecklistResult.respond_to?(name), "ChecklistResult.#{name} should not be defined"
    end
  end

  test "filters by status with where" do
    people = %i[ member member2 kid rookie ]
    rows = ChecklistResult.statuses.keys.each_with_index.to_h { |status, index| [ status, store(status, people[index]) ] }

    ChecklistResult.statuses.each_key do |status|
      assert_equal [ rows[status].id ], ChecklistResult.where(checklist: @checklist, status: status).pluck(:id)
    end
    assert_equal [ rows["met"].id ], ChecklistResult.where(checklist: @checklist).where.not(status: :not_met).where.not(status: %i[ pending exempt ]).pluck(:id)
    assert_equal [ rows["pending"].id ], ChecklistResult.where(checklist: @checklist, previous_status: :not_met).pluck(:id)
  end

  test "keeps the predicates and bang methods for both enums" do
    result = store("not_met")

    assert result.not_met?
    assert_not result.met?
    assert result.previously_met?

    result.met!
    assert result.reload.met?
    assert_equal "met", result.status
  end

  private
    def store(status, who = :member)
      ChecklistResult.create!(checklist: @checklist, person: person(who), status: status, computed_at: Time.current,
        previous_status: status == "pending" ? "not_met" : "met")
    end
end
