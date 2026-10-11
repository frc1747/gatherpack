require "test_helper"
require_relative "../support/signups_world"

class SignupSheetTest < ActiveSupport::TestCase
  include SignupsWorld

  setup do
    build_signups_world
    @sheet = create_world_sheet
  end

  test "slots exist for every position at every event" do
    cashier = @sheet.signup_positions.create!(name: "Cashier", capacity: 2)
    second = create_world_event("Second Game", Time.zone.parse("2026-10-31 10:00"))
    @sheet.signup_sheet_events.create!(event: second)
    @sheet.signup_positions.create!(name: "Cook")

    assert_equal 4, @sheet.signup_slots.count
    assert_equal [ @event.id, second.id ].sort, cashier.signup_slots.pluck(:event_id).sort

    SignupSlot.where(signup_position: cashier, event: second).delete_all
    @sheet.sync_slots!
    assert_equal 4, @sheet.signup_slots.count
  end

  test "removing an event or position is refused while it has sign-ups that aren't cancelled" do
    cashier = @sheet.signup_positions.create!(name: "Cashier")
    signup = Signup.place!(slot: slot_for(cashier), person: person(:student), signed_up_by: person(:student))
    link = @sheet.signup_sheet_events.find_by!(event: @event)

    assert_not link.destroy
    assert_match "has sign-ups", link.errors.full_messages.to_sentence
    assert_not cashier.destroy
    assert_not @sheet.destroy
    assert_match "Archive it instead", @sheet.errors.full_messages.to_sentence

    signup.cancel!
    assert link.reload.destroy
    assert_equal 0, cashier.signup_slots.count
    assert_not Signup.exists?(signup.id)
  end

  test "an event with sign-ups can't be deleted until they're all cancelled" do
    cashier = @sheet.signup_positions.create!(name: "Cashier")
    first = Signup.place!(slot: slot_for(cashier), person: person(:student), signed_up_by: person(:student))
    second = Signup.place!(slot: slot_for(cashier), person: person(:student2), signed_up_by: person(:student2))
    second.fulfilled!

    assert_not @event.reload.destroy
    # EventsController#destroy uses destroy!.
    assert_raises(ActiveRecord::RecordNotDestroyed) { @event.reload.destroy! }
    assert Event.exists?(@event.id)

    first.cancel!
    assert_raises(ActiveRecord::RecordNotDestroyed) { @event.reload.destroy! }

    second.cancel!
    @event.reload.destroy!
    assert_not Event.exists?(@event.id)
    assert_equal 0, SignupSlot.where(event_id: @event.id).count
    assert_not Signup.exists?(first.id)
  end

  test "the audience with no rules is the sheet's team and every team below it" do
    assert @sheet.open_to?(person(:student))
    assert @sheet.open_to?(person(:worker))
    assert_not @sheet.open_to?(person(:parent))
    assert_not @sheet.open_to?(person(:outsider))
  end

  test "audience rules include and exclude teams, badges and people" do
    @sheet.signup_audience_rules.create!(effect: :include, target_type: :team, team: @students)
    @sheet.signup_audience_rules.create!(effect: :include, target_type: :person, person: person(:outsider))
    @sheet.signup_audience_rules.create!(effect: :include, target_type: :badge, badge: @license_badge)
    @sheet.signup_audience_rules.create!(effect: :exclude, target_type: :person, person: person(:student2))

    audience = @sheet.reload.audience
    assert_includes audience, person(:student)
    assert_includes audience, person(:outsider)
    assert_includes audience, person(:worker)
    assert_not_includes audience, person(:student2)
    assert_not_includes audience, person(:concessions_manager)
  end

  test "a team rule can leave out managers" do
    @sheet.signup_audience_rules.create!(effect: :include, target_type: :team, team: @concessions, include_managers: false)

    assert @sheet.reload.open_to?(person(:worker))
    assert_not @sheet.open_to?(person(:concessions_manager))
  end

  test "takers are the signer and the people they can sign up through the sheet's relationship types" do
    assert_equal [ person(:student) ], @sheet.takers_for(person(:student)).to_a
    assert_empty @sheet.takers_for(person(:parent))

    @sheet.update!(others_relationship_type_ids: [ @parent_of.id, "" ])
    assert_equal [ person(:student) ], @sheet.takers_for(person(:parent)).to_a, "a parent signs up their child"
    assert_equal [ person(:student) ], @sheet.takers_for(person(:student)).to_a, "a child doesn't sign up their parent"

    @sheet.update!(others_relationship_type_ids: [ @sibling_of.id ])
    assert_equal [ person(:student) ], @sheet.takers_for(person(:sibling)).to_a
    @sheet.signup_audience_rules.create!(effect: :include, target_type: :person, person: person(:sibling))
    @sheet.signup_audience_rules.create!(effect: :include, target_type: :team, team: @students)
    assert_includes @sheet.reload.takers_for(person(:student)), person(:sibling), "a type that reads the same both ways works both ways"
  end

  test "on behalf of choices follow the sheet's mode" do
    @sheet.update!(others_relationship_type_ids: [ @parent_of.id ])
    parent, student = person(:parent), person(:student)

    assert_equal [ parent ], @sheet.on_behalf_of_choices_for(parent, parent).to_a

    @sheet.on_behalf_of_related_people!
    assert_equal [ parent, student ].sort_by(&:id), @sheet.on_behalf_of_choices_for(parent, parent).to_a.sort_by(&:id)

    @sheet.on_behalf_of_anyone!
    choices = @sheet.on_behalf_of_choices_for(parent, parent)
    assert_includes choices, parent
    assert_includes choices, person(:student2)
    assert_not_includes choices, person(:outsider)
  end

  test "organizer team ids are the union of the person's grants" do
    worker = person(:worker)

    with_organizer_grants("") do
      assert_empty SignupSheet.organizer_team_ids(worker)
    end
    with_organizer_grants("Sheet Organizer") do
      assert_equal [ @concessions.id ], SignupSheet.organizer_team_ids(worker)
    end
    with_organizer_grants("Sheet Organizer > Club") do
      assert_equal [ @club.id, @concessions.id ].sort, SignupSheet.organizer_team_ids(worker).sort
    end
    with_organizer_grants("sheet organizer > Club\nAlcohol License > Org\nNo Such Badge > Org\n") do
      assert_equal [ @org.id, @club.id, @concessions.id ].sort, SignupSheet.organizer_team_ids(worker).sort
      assert_empty SignupSheet.organizer_team_ids(person(:student))
    end
  end

  test "only admin-assigned badges grant" do
    @organizer_badge.update!(permission: :added_by_manager_or_self)

    with_organizer_grants("Sheet Organizer > Club") do
      assert_empty SignupSheet.organizer_team_ids(person(:worker))
    end
  end

  test "organizers are the listed people, admins, and managers of the team or above" do
    with_organizer_grants("Sheet Organizer > Club") do
      sheet = SignupSheet.create!(title: "Bake Sale", team: @concessions, created_by: person(:worker))

      assert sheet.organizer?(person(:worker)), "the creator is the first organizer"
      assert sheet.organizer?(person(:admin))
      assert sheet.organizer?(person(:concessions_manager))
      assert_not sheet.organizer?(person(:student))
      assert_not @sheet.organizer?(person(:concessions_manager)), "managing a team below doesn't run the sheet"
    end
  end

  test "only grant holders who reach the team can be added as organizers" do
    with_organizer_grants("Sheet Organizer > Club") do
      assert @sheet.signup_sheet_organizers.create(person: person(:worker)).persisted?
      refused = @sheet.signup_sheet_organizers.create(person: person(:student))
      assert_match "must hold an organizer badge", refused.errors.full_messages.to_sentence
    end
  end

  test "self or relative" do
    assert @sheet.self_or_relative?(person(:parent), person(:parent))
    assert @sheet.self_or_relative?(person(:parent), person(:student))
    assert @sheet.self_or_relative?(person(:student), person(:parent))
    assert_not @sheet.self_or_relative?(person(:parent), person(:sibling))
    assert_equal SignupSheet::SELF_APPROVAL_REASON, @sheet.self_approval_reason(person(:student), person(:sibling))
    assert_nil @sheet.self_approval_reason(person(:worker), person(:student))
  end

  test "names are visible to organizers, and to people who can sign up unless the sheet limits them" do
    assert @sheet.names_visible_to?(person(:student))
    assert_not @sheet.names_visible_to?(person(:outsider))

    @sheet.names_organizers!
    assert_not @sheet.names_visible_to?(person(:student))
    assert @sheet.names_visible_to?(person(:admin))
  end
end
