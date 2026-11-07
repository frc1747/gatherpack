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

  test "a pooled parent who isn't a guardian finds the wrapped count in the list and sees their family's row only" do
    with_settings(feature_badges: "true", commitments_organizers: "Commitment Organizer > Club") do
      families = create_world_commitment("Family shifts", group_relationship_type: @parent_of)
      families.commitment_sources.create!(kind: "checkins", subject: @outreach)
      dad = create_world_person("Dad")
      Relationship.create!(parent: dad, child: person(:member), relationship_type: @parent_of, created_by: person(:admin))
      checklist = Checklists::WrapCommitments.new.up.find { |made| made.title == "Family shifts" }

      sign_in dad.user
      with_checklists do
        get commitment_path(families)
        assert_redirected_to checklist_path(checklist)

        get checklists_path
        assert_response :success
        assert_select "a[href=?]", checklist_path(checklist)

        get checklist_path(checklist)
        assert_response :success
        assert_match person(:member).display_name, response.body
        assert_match "0 of 2 shifts", response.body
        assert_no_match person(:kid).display_name, response.body, "another family's row stays hidden"
        assert_no_match person(:member2).display_name, response.body

        get person_commitments_path(person(:member))
        assert_redirected_to checklists_path, "he can't open the member's own page, so he gets the list"
      end
    end
  end

  test "the form refuses to put a wrapped count in a group" do
    sign_in person(:admin).user
    wrapped = create_world_commitment("Wrapped shifts")
    checklist = Checklists::WrapCommitments.new.up.find { |made| made.title == "Wrapped shifts" }
    count = checklist.checklist_items.sole
    group = checklist.checklist_items.create!(kind: "any_of", label: "Either")
    with_checklists do
      patch checklist_checklist_item_path(checklist, count), params: { confirmed: "1", checklist_item: { label: count.label, parent_id: group.id, counts: "1",
        config: { base_amount: "2", unit: "shifts", additional_amount: "0", counts_when: "confirmed" } } }
      assert_response :unprocessable_entity
      assert_select ".alert-danger", text: "A wrapped commitment's count can't go in a group."
    end
    assert_nil count.reload.parent_id
    assert_equal count, wrapped.reload.checklist_item
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
      post checklist_checklist_items_path(@checklist), params: { confirmed: "1", checklist_item: { kind: "count", label: "Setup help", counts: "1", start_mode: "checklist",
        config: { base_amount: "3", unit: "shifts", group_relationship_type_id: @parent_of.id, additional_amount: "1", counts_when: "planned" } } }
      item = @checklist.checklist_items.find_by!(label: "Setup help")
      assert_redirected_to checklist_path(@checklist)
      assert_equal [ "Setup help", 3, @parent_of.id, 1 ], [ item.commitment.title, item.commitment.base_amount, item.commitment.group_relationship_type_id, item.commitment.additional_amount ]

      get edit_checklist_checklist_item_path(@checklist, item)
      assert_response :success
      assert_select "#sources a[href=?]", new_commitment_commitment_source_path(item.commitment, kind: "checkins")
      assert_select "#adjustments a[href=?]", new_commitment_commitment_adjustment_path(item.commitment)
      assert_select "select[name=?]", "checklist_item[config][group_relationship_type_id]"

      post commitment_commitment_sources_path(item.commitment), params: { commitment_source: { kind: "checkins", subject_id: @outreach.id, per: 1, credits: 1 } }
      assert_equal 1, item.commitment.commitment_sources.count
      assert_redirected_to edit_checklist_checklist_item_path(@checklist, item, anchor: "sources")
    end
  end

  test "a count item's source and credit pages belong to the item, in its words" do
    sign_in person(:admin).user
    with_checklists do
      get new_commitment_commitment_source_path(@commitment, kind: "checkins")
      assert_response :success
      assert_select ".breadcrumb a[href=?]", edit_checklist_checklist_item_path(@checklist, @item), text: "Shifts"
      assert_select ".breadcrumb a[href=?]", checklist_path(@checklist)
      assert_select "a[href=?]", edit_checklist_checklist_item_path(@checklist, @item, anchor: "sources"), text: "Cancel"
      assert_no_match(/commitment/i, css_select(".breadcrumb, h1").map(&:text).join(" "))

      get new_commitment_commitment_adjustment_path(@commitment)
      assert_response :success
      assert_select "h1", text: "Give or take credit on Shifts"
      assert_no_match(/commitment/i, css_select(".breadcrumb, h1").map(&:text).join(" "))

      outsider = @commitment.commitment_adjustments.new(person: person(:outsider), credits: 1, reason: "Nope")
      assert_not outsider.valid?
      assert_equal [ "doesn't owe Shifts" ], outsider.errors[:person]

      post commitment_commitment_adjustments_path(@commitment), params: { commitment_adjustment: { person_id: person(:member).id, credits: 1, reason: "Raffle" } }
      assert_redirected_to edit_checklist_checklist_item_path(@checklist, @item, anchor: "adjustments")
      delete commitment_commitment_adjustment_path(@commitment, CommitmentAdjustment.find_by!(reason: "Raffle"))
      assert_redirected_to edit_checklist_checklist_item_path(@checklist, @item, anchor: "adjustments")
    end
  end

  test "a commitment with no item keeps its own source pages" do
    sign_in person(:admin).user
    with_checklists do
      get new_commitment_commitment_source_path(@plain, kind: "checkins")
      assert_select ".breadcrumb", text: /Commitments.*Not on a checklist/m
      assert_select "a[href=?]", edit_commitment_path(@plain, anchor: "sources"), text: "Cancel"
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
