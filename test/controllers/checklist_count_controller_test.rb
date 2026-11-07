require "test_helper"
require_relative "../support/checklists_count_world"

class ChecklistCountControllerTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers
  include ChecklistsCountWorld

  setup do
    host! "localhost"
    build_commitments_world
    @checklist = create_count_checklist
    @item = add_count_item(@checklist)
    @commitment = @item.commitment
    @plain = create_world_commitment("Not on a checklist")
  end

  test "with checklists on, the commitment pages go to the checklist screens" do
    sign_in person(:admin).user
    with_checklists do
      get commitments_path
      assert_redirected_to checklists_path
      get commitment_path(@commitment)
      assert_redirected_to checklist_path(@checklist)
      get edit_commitment_path(@commitment)
      assert_redirected_to edit_checklist_checklist_item_path(@checklist, @item, anchor: "sources")
      get person_commitments_path(person(:member))
      assert_redirected_to person_checklists_path(person(:member))

      get commitment_path(@plain)
      assert_response :success
    end
  end

  test "with checklists off, the commitment pages stay" do
    sign_in person(:admin).user
    with_feature do
      get commitments_path
      assert_response :success
      get commitment_path(@commitment)
      assert_response :success
    end
  end

  test "someone who can't see a commitment isn't sent to its checklist" do
    sign_in person(:outsider).user
    with_checklists do
      get commitment_path(@commitment)
      assert_not_equal checklist_path(@checklist), URI(response.location.to_s).path
    end
  end

  test "an organizer adds a count item, then what counts and credit from its form" do
    sign_in person(:admin).user
    with_checklists do
      post checklist_checklist_items_path(@checklist), params: { checklist_item: { kind: "count", label: "Concessions", counts: "1", start_mode: "checklist",
        config: { base_amount: "3", unit: "shifts", group_relationship_type_id: @parent_of.id, additional_amount: "1", counts_when: "planned" } } }
      item = @checklist.checklist_items.find_by!(label: "Concessions")
      assert_redirected_to checklist_path(@checklist)
      assert_equal [ "Concessions", 3, @parent_of.id, 1 ], [ item.commitment.title, item.commitment.base_amount, item.commitment.group_relationship_type_id, item.commitment.additional_amount ]

      get edit_checklist_checklist_item_path(@checklist, item)
      assert_response :success
      assert_select "#sources a[href=?]", new_commitment_commitment_source_path(item.commitment, kind: "checkins")
      assert_select "#adjustments a[href=?]", new_commitment_commitment_adjustment_path(item.commitment)
      assert_select "select[name=?]", "checklist_item[config][group_relationship_type_id]"

      post commitment_commitment_sources_path(item.commitment), params: { commitment_source: { kind: "checkins", subject_id: @outreach.id, per: 1, credits: 1 } }
      assert_equal 1, item.commitment.commitment_sources.count
      follow_redirect!
      assert_redirected_to edit_checklist_checklist_item_path(@checklist, item, anchor: "sources")
    end
  end

  test "a badge item's form doesn't show the count parts" do
    sign_in person(:admin).user
    with_checklists do
      badge = @checklist.checklist_items.new(kind: "badge", label: "Safety")
      badge.config_params = { badge_ids: [ @organizer_badge.id ] }
      badge.save!
      get edit_checklist_checklist_item_path(@checklist, badge)
      assert_response :success
      assert_select "#sources", false
    end
  end

  test "the count item's form shows adjustments to its organizers, and organizers can't adjust their own family's" do
    @commitment.commitment_adjustments.create!(person: person(:member), credits: 1, reason: "Ran the raffle", created_by: person(:admin))
    @checklist.checklist_organizers.new(person: person(:organizer)).save!(validate: false)
    sign_in person(:organizer).user
    with_checklists(feature_badges: "true", commitments_organizers: "Commitment Organizer > Club") do
      get edit_checklist_checklist_item_path(@checklist, @item)
      assert_response :success
      assert_select "#adjustments", text: /Ran the raffle/

      post commitment_commitment_adjustments_path(@commitment), params: { commitment_adjustment: { person_id: person(:kid).id, credits: 1, reason: "Mine" } }
      assert_not CommitmentAdjustment.exists?(reason: "Mine")
    end
  end
end
