require "test_helper"
require_relative "../support/signups_world"

class SignupsControllerTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers
  include SignupsWorld

  setup do
    host! "localhost"
    travel_to Time.zone.parse("2026-10-01 12:00")
    build_signups_world
    @sheet = create_world_sheet
    @cashier = @sheet.signup_positions.create!(name: "Cashier", capacity: 3)
    @slot = slot_for(@cashier)
  end

  test "the list shows only sheets the person can see, their own first" do
    alpha = create_world_sheet("Alpha Sale")
    create_world_sheet("Draft Sheet", status: :draft)
    create_world_sheet("Other Org Sheet", team: @other_org)
    Signup.place!(slot: @slot, person: person(:student), signed_up_by: person(:student))
    sign_in person(:student).user

    get signup_sheets_path
    assert_response :success
    assert_select "tbody tr", count: 2
    assert_select "tbody tr:first-child##{ActionView::RecordIdentifier.dom_id(@sheet)}", text: /You're signed up for 1/
    assert_select "tbody tr:last-child##{ActionView::RecordIdentifier.dom_id(alpha)}"
    assert_select "a", text: "Draft Sheet", count: 0
    assert_select "a", text: "Other Org Sheet", count: 0
    assert_select "a", text: "Set up", count: 0
  end

  test "organizers also see their draft sheets, marked, with Set up" do
    draft = create_world_sheet("Draft Sheet", status: :draft)
    sign_in person(:concessions_manager).user
    get signup_sheets_path
    assert_select "a", text: "Draft Sheet", count: 0

    sign_in person(:admin).user
    get signup_sheets_path
    assert_select "tr##{ActionView::RecordIdentifier.dom_id(draft)}" do
      assert_select ".badge", text: "Draft"
      assert_select "a[href=?]", edit_signup_sheet_path(draft), text: "Set up"
    end
  end

  test "a member signs up for themselves" do
    sign_in person(:student).user

    get signup_sheet_path(@sheet)
    assert_select "a[href=?]", new_signup_sheet_signup_path(@sheet, slot_id: @slot.id), text: "Sign up"
    get new_signup_sheet_signup_path(@sheet, slot_id: @slot.id)
    assert_response :success
    assert_select "input[name='signup[person_id]']", count: 0
    assert_select "input[name='signup[on_behalf_of_id]']", count: 0

    assert_difference "Signup.count" do
      post signup_sheet_signups_path(@sheet), params: { signup: { signup_slot_id: @slot.id, extra_people: 1, extra_names: "Sam", note: "Late" } }
    end
    assert_redirected_to signup_sheet_path(@sheet)
    signup = Signup.last
    assert_equal [ person(:student) ] * 3, [ signup.person, signup.signed_up_by, signup.on_behalf_of ]
    assert_equal [ 1, "Sam", "Late" ], [ signup.extra_people, signup.extra_names, signup.note ]

    get signup_sheet_path(@sheet)
    assert_select "#my_signups", text: /Cashier/
    assert_select "##{ActionView::RecordIdentifier.dom_id(@slot)}", text: /2 of 3 filled.*Student World \(\+1\)/m
  end

  test "a parent signs up their child when the sheet allows it, and not otherwise" do
    sign_in person(:parent).user

    assert_no_difference "Signup.count" do
      post signup_sheet_signups_path(@sheet), params: { signup: { signup_slot_id: @slot.id, person_id: person(:student).id } }
    end
    get signup_sheet_path(@sheet)
    assert_redirected_to root_path

    @sheet.update!(others_relationship_type_ids: [ @parent_of.id ])
    get new_signup_sheet_signup_path(@sheet, slot_id: @slot.id)
    assert_select "input[name='signup[person_id]'][value=?]", person(:student).id

    assert_no_difference "Signup.count" do
      post signup_sheet_signups_path(@sheet), params: { signup: { signup_slot_id: @slot.id, person_id: person(:student2).id } }
    end
    assert_difference "Signup.count" do
      post signup_sheet_signups_path(@sheet), params: { signup: { signup_slot_id: @slot.id, person_id: person(:student).id } }
    end
    signup = Signup.last
    assert_equal [ person(:student), person(:parent) ], [ signup.person, signup.signed_up_by ]

    get signup_sheet_path(@sheet)
    assert_select "#my_signups", text: /For Student World/
  end

  test "on behalf of follows the sheet's mode" do
    sign_in person(:student).user
    params = { signup: { signup_slot_id: @slot.id, on_behalf_of_id: person(:student2).id } }

    assert_no_difference "Signup.count" do
      post signup_sheet_signups_path(@sheet), params: params
    end
    assert_response :unprocessable_entity
    assert_select ".alert", text: /You can't sign up on behalf of StudentTwo World/

    @sheet.on_behalf_of_anyone!
    get new_signup_sheet_signup_path(@sheet, slot_id: @slot.id)
    assert_select "input[name='signup[on_behalf_of_id]'][value=?]", person(:student2).id
    assert_difference "Signup.count" do
      post signup_sheet_signups_path(@sheet), params: params
    end
    signup = Signup.last
    assert_equal [ person(:student), person(:student2) ], [ signup.person, signup.on_behalf_of ]

    sign_in person(:student2).user
    get signup_sheet_path(@sheet)
    assert_select "#my_signups", text: /Taken for you by Student World/
    assert_select "#my_signups a", text: "Change", count: 0
    assert_select "#my_signups button", text: "Cancel", count: 0
    patch signup_sheet_signup_path(@sheet, signup), params: { signup: { note: "Mine" } }
    delete signup_sheet_signup_path(@sheet, signup)
    assert signup.reload.active?
    assert_nil signup.note
  end

  test "someone who fails a rule is refused with the reason" do
    @cashier.signup_position_rules.create!(kind: :badge, badge_ids: [ @license_badge.id ])
    sign_in person(:student).user

    get signup_sheet_path(@sheet)
    assert_select "##{ActionView::RecordIdentifier.dom_id(@slot)}", text: /Needs the Alcohol License badge/
    assert_select "a", text: "Sign up", count: 0

    assert_no_difference "Signup.count" do
      post signup_sheet_signups_path(@sheet), params: { signup: { signup_slot_id: @slot.id } }
    end
    assert_response :unprocessable_entity
    assert_select ".alert", text: /Needs the Alcohol License badge/
  end

  test "a full slot is refused" do
    @cashier.update!(capacity: 1)
    Signup.place!(slot: @slot, person: person(:student2), signed_up_by: person(:student2))
    sign_in person(:student).user

    get signup_sheet_path(@sheet)
    assert_select "##{ActionView::RecordIdentifier.dom_id(@slot)}", text: /1 of 1 filled.*Full/m

    assert_no_difference "Signup.count" do
      post signup_sheet_signups_path(@sheet), params: { signup: { signup_slot_id: @slot.id } }
    end
    assert_response :unprocessable_entity
    assert_select ".alert", text: /This slot is full/
  end

  test "items are capped at what's still needed" do
    pizza = @sheet.signup_positions.create!(name: "Pizza", kind: :items, unit: "pizzas", capacity: 6, question: "What kind?")
    slot = slot_for(pizza)
    Signup.place!(slot: slot, person: person(:student2), signed_up_by: person(:student2), quantity: 4, answer: "Cheese")
    sign_in person(:student).user

    get signup_sheet_path(@sheet)
    assert_select "##{ActionView::RecordIdentifier.dom_id(slot)}", text: /4 of 6 pizzas.*StudentTwo World \(Cheese, 4\)/m
    get new_signup_sheet_signup_path(@sheet, slot_id: slot.id)
    assert_select "input[name='signup[quantity]'][max='2']"

    assert_no_difference "Signup.count" do
      post signup_sheet_signups_path(@sheet), params: { signup: { signup_slot_id: slot.id, quantity: 3 } }
    end
    assert_response :unprocessable_entity
    assert_select ".alert", text: /Only 2 pizzas still needed/

    assert_difference "Signup.count" do
      post signup_sheet_signups_path(@sheet), params: { signup: { signup_slot_id: slot.id, quantity: 2, answer: "Veggie" } }
    end
    assert_equal [ 2, "Veggie" ], [ Signup.last.quantity, Signup.last.answer ]
  end

  test "a required answer is needed" do
    @cashier.update!(question: "Shirt size?", question_required: true)
    sign_in person(:student).user

    assert_no_difference "Signup.count" do
      post signup_sheet_signups_path(@sheet), params: { signup: { signup_slot_id: @slot.id, answer: "" } }
    end
    assert_response :unprocessable_entity
    assert_select ".alert", text: /Answer "Shirt size\?"/

    assert_difference "Signup.count" do
      post signup_sheet_signups_path(@sheet), params: { signup: { signup_slot_id: @slot.id, answer: "M" } }
    end
  end

  test "a member changes their sign-up" do
    signup = Signup.place!(slot: @slot, person: person(:student), signed_up_by: person(:student))
    sign_in person(:student).user

    get edit_signup_sheet_signup_path(@sheet, signup)
    assert_response :success
    patch signup_sheet_signup_path(@sheet, signup), params: { signup: { extra_people: 1, extra_names: "Sam", note: "Bringing a friend" } }
    assert_redirected_to signup_sheet_path(@sheet)
    assert_equal [ 1, "Sam", "Bringing a friend" ], signup.reload.slice(:extra_people, :extra_names, :note).values

    patch signup_sheet_signup_path(@sheet, signup), params: { signup: { extra_people: 5 } }
    assert_response :unprocessable_entity
    assert_select ".alert", text: /Only 3 places left/
    assert_equal 1, signup.reload.extra_people
  end

  test "a member cancels before the cutoff, and not after" do
    signup = Signup.place!(slot: @slot, person: person(:student), signed_up_by: person(:student))
    sign_in person(:student).user

    get signup_sheet_path(@sheet)
    assert_select "#my_signups button", text: "Cancel"
    assert_no_difference "Signup.count" do
      delete signup_sheet_signup_path(@sheet, signup)
    end
    assert_redirected_to signup_sheet_path(@sheet)
    assert signup.reload.cancelled?

    late = Signup.place!(slot: @slot, person: person(:student), signed_up_by: person(:student))
    travel_to @event.start_time + 1.minute
    get signup_sheet_path(@sheet)
    assert_select "#my_signups button", text: "Cancel", count: 0
    assert_select "#my_signups", text: /Ask an organizer to cancel/
    delete signup_sheet_signup_path(@sheet, late)
    assert late.reload.active?
  end

  test "someone outside the audience can't see the sheet or sign up" do
    sign_in person(:outsider).user

    get new_signup_sheet_signup_path(@sheet, slot_id: @slot.id)
    assert_redirected_to root_path
    assert_no_difference "Signup.count" do
      post signup_sheet_signups_path(@sheet), params: { signup: { signup_slot_id: @slot.id } }
    end
  end

  test "a closed sheet shows sign-ups read-only and refuses new ones" do
    signup = Signup.place!(slot: @slot, person: person(:student), signed_up_by: person(:student))
    @sheet.closed!
    sign_in person(:student).user

    get signup_sheet_path(@sheet)
    assert_response :success
    assert_select "#my_signups", text: /Cashier/
    assert_select "a", text: "Sign up", count: 0
    assert_select "#my_signups a", text: "Change", count: 0

    get new_signup_sheet_signup_path(@sheet, slot_id: @slot.id)
    assert_redirected_to root_path
    assert_no_difference "Signup.count" do
      post signup_sheet_signups_path(@sheet), params: { signup: { signup_slot_id: @slot.id } }
    end
    delete signup_sheet_signup_path(@sheet, signup)
    assert signup.reload.active?
  end

  test "disabled slots don't show and can't be taken" do
    @slot.update!(disabled: true)
    sign_in person(:student).user

    get signup_sheet_path(@sheet)
    assert_select "##{ActionView::RecordIdentifier.dom_id(@slot)}", count: 0
    get new_signup_sheet_signup_path(@sheet, slot_id: @slot.id)
    assert_response :not_found
  end
end
