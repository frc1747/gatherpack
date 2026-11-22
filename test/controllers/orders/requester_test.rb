require "test_helper"
require "support/orders_world"

# The requester's screens (spec §3.16, §8 "Requester tests").
class Orders::RequesterTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers
  include OrdersWorld

  setup do
    @world = build_orders_world
    sign_in @world.requester.user
  end

  def line_params(**fields)
    { "0" => { quantity: "1", vendor_choice: "not_sure" }.merge(fields) }
  end

  def create_request(lines:, submit: true, **fields)
    post orders_requests_url, params: { order_request: { lines: lines }.merge(fields) }.merge(submit ? { submit_request: "1" } : {})
    OrderRequest.where(requested_by: @world.requester).order(:created_at).last
  end

  test "an item with only a link submits" do
    with_orders(@world) do
      order_request = create_request(lines: line_params(url: "https://shop.example/thing"))

      assert_redirected_to orders_request_url(order_request)
      assert order_request.submitted?
      assert_equal "https://shop.example/thing", order_request.order_lines.sole.url
    end
  end

  test "an item with only a description submits, and its description becomes the title" do
    with_orders(@world) do
      order_request = create_request(lines: line_params(description: "Zip ties"))

      assert order_request.submitted?
      assert_equal "Zip ties", order_request.title
      assert order_request.order_lines.sole.not_sure?
    end
  end

  test "an item with neither a link nor a description is refused" do
    with_orders(@world) do
      assert_no_difference -> { OrderRequest.count } do
        post orders_requests_url, params: { submit_request: "1",
          order_request: { lines: line_params(manufacturer: "Acme") } }
      end
      assert_response :unprocessable_entity
      assert_match "Item 1: Give a link or say what it is", response.body
    end
  end

  test "a request with no items isn't sent for approval" do
    with_orders(@world) do
      post orders_requests_url, params: { submit_request: "1", order_request: { purpose: "Spares", lines: line_params } }

      assert_response :unprocessable_entity
      assert_match "Add at least one item", response.body
      assert OrderRequest.where(requested_by: @world.requester).sole.draft?
    end
  end

  test "?url= opens the form with the link, its store and the part number filled in" do
    with_orders(@world) do
      get new_orders_request_url(url: "https://www.partsdepot.example/p/AB-123?ref=x")

      assert_response :success
      assert_select "input[name='order_request[lines][0][url]'][value=?]", "https://www.partsdepot.example/p/AB-123?ref=x"
      assert_select "select[name='order_request[lines][0][vendor_choice]'] option[selected][value=?]", @world.preferred_vendor.id
      assert_select "input[name='order_request[lines][0][vendor_part_number]'][value=?]", "AB-123"
      assert_select "[data-field=match]", "From Parts Depot · part AB-123"
    end
  end

  test "a link the vendor's pattern doesn't match fills no part number" do
    with_orders(@world) do
      get new_orders_request_url(url: "https://partsdepot.example/search?q=gears")

      assert_select "select[name='order_request[lines][0][vendor_choice]'] option[selected][value=?]", @world.preferred_vendor.id
      assert_select "input[name='order_request[lines][0][vendor_part_number]']:not([value])"
    end
  end

  test "a link from an unknown store sets Other store with its host" do
    with_orders(@world) do
      get new_orders_request_url(url: "https://www.cornershop.example/item/9")

      assert_select "select[name='order_request[lines][0][vendor_choice]'] option[selected][value=other]"
      assert_select "input[name='order_request[lines][0][other_vendor_name]'][value=?]", "cornershop.example"
    end
  end

  test "the form gives the link box every active vendor's domains and pattern, but no account notes" do
    with_orders(@world) do
      @world.preferred_vendor.update!(account_note: "Customer 12345")
      Vendor.create!(name: "Closed Shop", domains: [ "closed.example" ], active: false)
      get new_orders_request_url

      vendors = JSON.parse(css_select("form[data-controller=order-form]").first["data-order-form-vendors-value"])
      assert_equal [ "Hardware Barn", "Parts Depot" ].sort, vendors.map { |vendor| vendor["name"] }.sort
      assert_equal "/p/([A-Z0-9-]+)", vendors.find { |vendor| vendor["name"] == "Parts Depot" }["pattern"]
      assert_no_match "Customer 12345", response.body
    end
  end

  test "the store chosen on the form is saved: a vendor, another store, or not sure" do
    with_orders(@world) do
      order_request = create_request(submit: false, lines: {
        "0" => { description: "Gear", quantity: "2", vendor_choice: @world.preferred_vendor.id, vendor_part_number: "G-1", estimated_unit_price: "$4.50" },
        "1" => { description: "Tape", quantity: "1", vendor_choice: "other", other_vendor_name: "Corner Hardware" },
        "2" => { description: "Something", quantity: "1", vendor_choice: "not_sure" }
      })

      gear, tape, something = order_request.order_lines.to_a
      assert_equal @world.preferred_vendor, gear.vendor
      assert_equal 450, gear.estimated_unit_price_cents
      assert_equal "Corner Hardware", tape.other_vendor_name
      assert something.not_sure?
    end
  end

  test "a price that isn't a number names its item" do
    with_orders(@world) do
      post orders_requests_url, params: { order_request: { lines: line_params(description: "Gear", estimated_unit_price: "cheap") } }

      assert_response :unprocessable_entity
      assert_match "Item 1: the price isn&#39;t a number", response.body
    end
  end

  test "a draft saves without a button, then later saves change the same draft" do
    with_orders(@world) do
      post orders_requests_url, params: { order_request: { lines: line_params(description: "Gea") } }, as: :json
      # Autosave posts the form as multipart; this is the same params as JSON.
      assert_response :success
      data = response.parsed_body
      order_request = OrderRequest.find(data["id"])
      assert order_request.draft?
      line_id = data["lines"]["0"]
      assert_equal order_request.order_lines.sole.id, line_id

      assert_no_difference -> { OrderRequest.count } do
        patch data["update_url"], params: { order_request: { lines: {
          "0" => { id: line_id, description: "Gear", quantity: "3" },
          "1700000000000" => { description: "Belt", quantity: "1" }
        } } }, as: :json
      end
      assert_response :success
      assert_equal %w[Gear Belt], order_request.reload.order_lines.map(&:description)
      assert_equal 3, order_request.order_lines.first.quantity
      assert response.parsed_body["lines"].key?("1700000000000")
      assert order_request.draft?
      assert_empty order_request.events
    end
  end

  test "autosave keeps nothing from an untouched form" do
    with_orders(@world) do
      assert_no_difference -> { OrderRequest.count } do
        post orders_requests_url, params: { order_request: { lines: line_params } }, as: :json
      end
      assert response.parsed_body["skipped"]
    end
  end

  test "a removed item leaves the draft" do
    with_orders(@world) do
      order_request = draft_request(@world, lines: [ { description: "Gear" }, { description: "Belt" } ])
      gear, belt = order_request.order_lines.to_a

      patch orders_request_url(order_request), params: { order_request: { lines: {
        "0" => { id: gear.id, description: "Gear" }, "1" => { id: belt.id, _destroy: "1" }
      } } }, as: :json

      assert_equal [ "1" ], response.parsed_body["removed"]
      assert_equal [ gear ], order_request.reload.order_lines.to_a
    end
  end

  test "submitting a saved draft sends it for approval" do
    with_orders(@world) do
      order_request = draft_request(@world)
      line = order_request.order_lines.sole

      patch orders_request_url(order_request), params: { submit_request: "1",
        order_request: { needed_by: "2030-01-15", purpose: "Spares", lines: { "0" => { id: line.id, description: "Gear" } } } }

      assert_redirected_to orders_request_url(order_request)
      order_request.reload
      assert order_request.submitted?
      assert_equal Date.new(2030, 1, 15), order_request.needed_by
      assert_equal "Spares", order_request.purpose
    end
  end

  test "a request needing changes is updated and sent back, and its changes show in the timeline" do
    with_orders(@world) do
      order_request = submitted_request(@world)
      order_request.decide!(:changes_requested, by: @world.mentor, comment: "Which size?")
      line = order_request.order_lines.sole

      get edit_orders_request_url(order_request)
      assert_response :success
      assert_match "Which size?", response.body
      assert_select "button[name=submit_request]", "Send back for approval"

      patch orders_request_url(order_request), params: { submit_request: "1",
        order_request: { lines: { "0" => { id: line.id, description: "Gear, 20 teeth", quantity: "2" } } } }

      assert_redirected_to orders_request_url(order_request)
      assert order_request.reload.submitted?
      follow_redirect!
      assert_match "Sent back for approval", response.body
      assert_match "What it is: Gear → Gear, 20 teeth", response.body
      assert_match "How many: 1 → 2", response.body
    end
  end

  test "the funding source is hidden from requesters unless they may pick it" do
    with_orders(@world) do
      source = FundingSource.create!(name: "Build budget", team: @world.robotics)

      get new_orders_request_url
      assert_select "select[name='order_request[funding_source_id]']", count: 0

      with_settings(orders_settings(@world, orders_requesters_pick_funding: "true")) do
        Orders::Current.reset
        get new_orders_request_url
        assert_select "select[name='order_request[funding_source_id]'] option", text: "Build budget"

        order_request = create_request(lines: line_params(description: "Gear"), funding_source_id: source.id)
        assert_equal source, order_request.funding_source
      end
    end
  end

  test "a requester who may not pick funding can't set it by posting it" do
    with_orders(@world) do
      source = FundingSource.create!(name: "Build budget", team: @world.robotics)

      post orders_requests_url, params: { order_request: { funding_source_id: source.id, lines: line_params(description: "Gear") } }

      assert_response :unprocessable_entity
      assert_nil OrderRequest.find_by(requested_by: @world.requester)&.funding_source
    end
  end

  test "the team box appears only for someone on more than one team" do
    with_orders(@world) do
      get new_orders_request_url
      assert_select "select[name='order_request[team_id]']", count: 0

      Membership.create!(person: @world.requester, team: @world.build)
      Orders::Current.reset
      get new_orders_request_url
      assert_select "select[name='order_request[team_id]'] option", 2
    end
  end

  test "the needed-by picks include the team's next event" do
    with_orders(@world) do
      event_type = EventType.first || EventType.create!(name: "Meeting")
      Event.create!(name: "Regional", team: @world.robotics, event_type: event_type,
        start_time: 10.days.from_now, end_time: 10.days.from_now + 2.hours)

      get new_orders_request_url
      assert_select "label", "ASAP"
      assert_select "label", "This week"
      assert_select "label", "Before Regional"
      assert_select "input[name=needed_by_pick][value=?]", (10.days.from_now.to_date - 1).iso8601
      assert_select "label", "No rush"
    end
  end

  test "estimated shipping isn't in the total a requester sees" do
    with_orders(@world) do
      order_request = submitted_request(@world, lines: [ { description: "Gear", price: 10 } ])
      order_request.update_columns(estimated_shipping_cents: 700)

      get orders_request_url(order_request)
      assert_select "p strong", "$10.00"

      sign_in @world.manager.user
      get orders_request_url(order_request)
      assert_select "p strong", "$17.00"
    end
  end

  test "the request page lists the items and the timeline with approvals" do
    with_orders(@world) do
      order_request = approved_request(@world, lines: [ { description: "Gear", url: "https://partsdepot.example/p/G-1", price: 3 } ])

      get orders_request_url(order_request)
      assert_response :success
      assert_select "#items", /Gear/
      assert_select "#items a[href=?]", "https://partsdepot.example/p/G-1"
      assert_select "#timeline .orders-approval", /Approved \(Approval\)/
      assert_select "#timeline", /Sent for approval/
    end
  end

  test "a draft can be deleted, but not a submitted request" do
    with_orders(@world) do
      draft = draft_request(@world)
      delete orders_request_url(draft)
      assert_redirected_to orders_requests_url(mine: 1)
      assert_not OrderRequest.exists?(draft.id)

      submitted = submitted_request(@world)
      delete orders_request_url(submitted)
      assert OrderRequest.exists?(submitted.id)
    end
  end

  test "the requester cancels a request before anything is ordered" do
    with_orders(@world) do
      order_request = submitted_request(@world)

      post cancel_orders_request_url(order_request)
      assert order_request.reload.cancelled?
    end
  end

  test "duplicate makes a new draft copy with the same items, team and funding source" do
    with_orders(@world) do
      source = FundingSource.create!(team: @world.robotics, name: "Parts Fund", kind: :general)
      order_request = approved_request(@world, title: "Gears", funding_source: source, lines: [ { description: "Gear", price: 3 } ])

      assert_difference -> { OrderRequest.count } do
        with_settings(orders_settings(@world, orders_requesters_pick_funding: "true")) do
          post order_again_orders_request_url(order_request)
        end
      end
      draft = OrderRequest.order(:created_at).last
      assert_redirected_to edit_orders_request_url(draft)
      assert_equal "Duplicated. Check it, then save.", flash[:notice]
      assert draft.draft?
      assert_equal "Gears (copy)", draft.title
      assert_equal source, draft.funding_source
      assert_equal [ "Gear" ], draft.order_lines.map(&:description)
      assert_empty draft.order_approvals
      assert_empty draft.events
    end
  end

  test "duplicate works on a draft, and leaves the funding source off for someone who can't pick it" do
    with_orders(@world) do
      source = FundingSource.create!(team: @world.robotics, name: "Parts Fund", kind: :general)
      draft = draft_request(@world, funding_source: source)
      post order_again_orders_request_url(draft)
      copy = OrderRequest.order(:created_at).last
      assert_not_equal draft, copy
      assert_nil copy.funding_source
    end
  end

  test "a teammate follows and stops following" do
    with_orders(@world) do
      order_request = submitted_request(@world)
      sign_in @world.teammate.user

      post follow_orders_request_url(order_request)
      assert order_request.reload.watched_by?(@world.teammate)

      delete follow_orders_request_url(order_request)
      assert_not order_request.reload.watched_by?(@world.teammate)
    end
  end

  test "followers can comment, and the comment shows in the timeline" do
    with_orders(@world) do
      order_request = submitted_request(@world)
      sign_in @world.teammate.user

      post comment_orders_request_url(order_request), params: { comment: "I can pick it up" }
      follow_redirect!
      assert_select "#timeline", /I can pick it up/
    end
  end

  test "the requester adds a follower from the team, and only from it" do
    with_orders(@world) do
      order_request = submitted_request(@world)

      post orders_request_watchers_url(order_request), params: { person_id: @world.outsider.id }
      assert_not order_request.reload.watched_by?(@world.outsider)

      post orders_request_watchers_url(order_request), params: { person_id: @world.teammate.id }
      assert order_request.reload.watched_by?(@world.teammate)

      watcher = order_request.order_request_watchers.sole
      delete orders_request_watcher_url(order_request, watcher)
      assert_not order_request.reload.watched_by?(@world.teammate)
    end
  end

  test "someone else can't add followers" do
    with_orders(@world) do
      order_request = submitted_request(@world)
      sign_in @world.teammate.user

      post orders_request_watchers_url(order_request), params: { person_id: @world.builder.id }
      assert_not order_request.reload.watched_by?(@world.builder)
    end
  end

  test "a follower who holds an approver grant can approve, and a relative can't" do
    with_orders(@world) do
      order_request = submitted_request(@world)
      post orders_request_watchers_url(order_request), params: { person_id: @world.mentor.id }
      post orders_request_watchers_url(order_request), params: { person_id: @world.parent.id }
      order_request.reload
      assert order_request.watched_by?(@world.mentor)
      assert order_request.watched_by?(@world.parent)

      Orders::Current.reset
      assert OrderRequestPolicy.new(@world.mentor.user, order_request).decide?
      assert_not OrderRequestPolicy.new(@world.parent.user, order_request).decide?
    end
  end

  test "My requests lists the viewer's drafts, linked to finish them" do
    with_orders(@world) do
      draft = draft_request(@world, title: "Half done")

      get orders_requests_url(mine: 1)
      assert_select "a[href=?]", edit_orders_request_url(draft, only_path: true), /Half done/
    end
  end

  test "someone else's draft can't be opened or changed" do
    with_orders(@world) do
      draft = draft_request(@world)
      sign_in @world.teammate.user

      get edit_orders_request_url(draft)
      assert_response :not_found
      # The not-found response doesn't keep the test sign-in, so sign in again.
      sign_in @world.teammate.user
      patch orders_request_url(draft), params: { order_request: { purpose: "Mine now" } }
      assert_response :not_found
      assert_nil draft.reload.purpose
    end
  end

  # 1×1 PNG.
  PNG = Base64.decode64("iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNk+M9QDwADhgGAWjR9awAAAABJRU5ErkJggg==")

  test "a link that isn't a web page is refused, and a link without a scheme is taken as https" do
    with_orders(@world) do
      assert_no_difference -> { OrderRequest.count } do
        post orders_requests_url, params: { submit_request: "1",
          order_request: { lines: line_params(url: "javascript:alert(document.cookie)") } }
      end
      assert_response :unprocessable_entity
      assert_match "Item 1: The link must be a web page", response.body

      order_request = create_request(lines: line_params(url: "shop.example/p/9"))
      assert_equal "https://shop.example/p/9", order_request.order_lines.sole.url
    end
  end

  test "?url= with a link that isn't a web page fills nothing" do
    with_orders(@world) do
      get new_orders_request_url(url: "javascript:alert(1)")

      assert_response :success
      assert_select "input[name='order_request[lines][0][url]']:not([value])"
      assert_no_match "javascript:alert", response.body
    end
  end

  test "a stored link that isn't a web page shows as text, never as a link" do
    with_orders(@world) do
      order_request = submitted_request(@world, lines: [ { description: "Gear", url: "https://shop.example/g" } ])
      order_request.order_lines.sole.update_column(:url, "javascript:alert(1)")
      sign_in @world.manager.user

      get orders_request_url(order_request)
      assert_select "#items", /javascript:alert\(1\)/
      assert_select "a[href^='javascript']", count: 0
    end
  end

  test "saving the edit form keeps a funding source that is no longer active" do
    with_orders(@world) do
      source = FundingSource.create!(name: "Old budget", team: @world.robotics)
      order_request = submitted_request(@world)
      order_request.edit!({ funding_source_id: source.id }, by: @world.manager)
      source.update!(active: false)
      sign_in @world.manager.user

      get edit_orders_request_url(order_request)
      assert_select "select[name='order_request[funding_source_id]'] option[selected][value=?]", source.id

      line = order_request.order_lines.sole
      patch orders_request_url(order_request), params: { order_request: { purpose: "Fixed a typo", funding_source_id: source.id,
        lines: { "0" => { id: line.id, description: "Gear" } } } }
      assert_equal source, order_request.reload.funding_source
      assert_equal "Fixed a typo", order_request.purpose
    end
  end

  test "a draft takes no comments, and deleting it never fails with an error page" do
    with_orders(@world) do
      draft = draft_request(@world)

      post comment_orders_request_url(draft), params: { comment: "Note to self" }
      assert_empty draft.events.reload

      delete orders_request_url(draft)
      assert_redirected_to orders_requests_url(mine: 1)
      assert_not OrderRequest.exists?(draft.id)
    end
  end

  test "a draft with a timeline is refused deletion with a message" do
    with_orders(@world) do
      draft = draft_request(@world)
      draft.log!(:edited, by: @world.requester)

      delete orders_request_url(draft), headers: { "HTTP_REFERER" => orders_request_url(draft) }
      assert_redirected_to orders_request_url(draft)
      assert_equal "This draft has a timeline, so cancel it instead.", flash[:alert]
      assert OrderRequest.exists?(draft.id)
    end
  end

  test "a line entry extension links the item it picked, and only a type it registered" do
    with_orders(@world) do
      Orders.line_entry_extensions.register(:test_picker, partial: nil, item_types: [ "Team" ])
      get new_orders_request_url
      assert_select "[data-order-line] input[type=hidden][data-field=item_type][name='order_request[lines][0][item_type]']"
      assert_select "[data-order-line] input[type=hidden][data-field=item_id][name='order_request[lines][0][item_id]']"

      order_request = create_request(submit: false,
        lines: line_params(description: "Gear", item_type: "Team", item_id: @world.robotics.id))
      line = order_request.order_lines.sole
      assert_equal @world.robotics, line.item

      # Posted back unchanged with the form, the link stays.
      patch orders_request_url(order_request), params: { order_request: { lines: {
        "0" => { id: line.id, description: "Gear", item_type: "Team", item_id: @world.robotics.id } } } }
      assert_equal @world.robotics, line.reload.item

      assert_no_difference -> { OrderRequest.count } do
        post orders_requests_url, params: { order_request: {
          lines: line_params(description: "Gear", item_type: "User", item_id: @world.requester.user.id) } }
      end
      assert_response :unprocessable_entity
      assert_match "Item 1: that item can&#39;t be linked here", response.body
    ensure
      Orders.line_entry_extensions.unregister(:test_picker)
    end
  end

  test "photos show as resized thumbnails, not the camera original" do
    with_orders(@world) do
      order_request = draft_request(@world)
      line = order_request.order_lines.sole
      line.photo.attach(io: StringIO.new(PNG), filename: "part.png", content_type: "image/png")

      get orders_request_url(order_request)
      assert_select "#items img.orders-line-photo[src*='/representations/']"
      assert_select "#items img[src*='/blobs/redirect/']", count: 0

      get edit_orders_request_url(order_request)
      assert_select "img.orders-line-photo[src*='/representations/']"
    end
  end
end
