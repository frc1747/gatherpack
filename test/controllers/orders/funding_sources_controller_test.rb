require "test_helper"
require "support/orders_world"

class Orders::FundingSourcesControllerTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers
  include OrdersWorld

  setup do
    @world = build_orders_world
    @source = FundingSource.create!(team: @world.robotics, name: "Build Budget", kind: :restricted, amount: 1000,
      restriction: "Robot parts only", giver: "Local Foundation", reference: "Grant 77", spent_outside: 50)
  end

  def gift_letter(name = "gift", text = "Thank you")
    file = Tempfile.new([ name, ".txt" ])
    file.write(text)
    file.close
    Rack::Test::UploadedFile.new(file.path, "text/plain")
  end

  test "someone outside the team sees the name but not the money or the giver" do
    with_orders(@world) do
      sign_in @world.outsider.user

      get orders_funding_sources_url
      assert_response :success
      assert_match "Build Budget", response.body
      assert_no_match "$950.00", response.body

      get orders_funding_source_url(@source)
      assert_response :success
      assert_no_match "Local Foundation", response.body
      assert_no_match "Grant 77", response.body
      assert_select "a", text: "Report", count: 0
      assert_select "a", text: "Edit", count: 0
    end
  end

  test "a funding manager sees the numbers and restricted fields" do
    with_orders(@world) do
      sign_in @world.funding_manager.user

      get orders_funding_source_url(@source)
      assert_match "Local Foundation", response.body
      assert_match "Grant 77", response.body
      assert_match "$950.00", response.body
      assert_select "a", text: "Edit"
    end
  end

  test "an approver of the team sees the restricted fields but can't edit" do
    with_orders(@world) do
      sign_in @world.mentor.user

      get orders_funding_source_url(@source)
      assert_match "Local Foundation", response.body
      assert_select "a", text: "Edit", count: 0

      patch orders_funding_source_url(@source), params: { funding_source: { name: "Mine now" } }
      assert_redirected_to root_url
      assert_equal "Build Budget", @source.reload.name
    end
  end

  test "a requester can't create a source" do
    with_orders(@world) do
      sign_in @world.requester.user

      assert_no_difference "FundingSource.count" do
        post orders_funding_sources_url, params: { funding_source: { team_id: @world.robotics.id, name: "Mine" } }
      end
      assert_redirected_to root_url
    end
  end

  test "a funding manager creates a source with a document for a team in reach" do
    with_orders(@world) do
      sign_in @world.funding_manager.user

      get new_orders_funding_source_url
      assert_response :success
      assert_difference "FundingSource.count", 1 do
        post orders_funding_sources_url, params: { funding_source: {
          team_id: @world.robotics.id, name: "Gift", kind: "restricted", amount: "2500.50", restriction: "Tools",
          giver: "Neighbor", report_due_on: "2027-01-31", spent_outside: "100", spent_outside_as_of: "2026-10-01", active: "1",
          documents: [ gift_letter ]
        } }
      end
      source = FundingSource.find_by!(name: "Gift")
      assert_redirected_to orders_funding_source_url(source)
      assert_equal 250050, source.amount_cents
      assert_equal 10000, source.spent_outside_cents
      assert_equal Date.new(2027, 1, 31), source.report_due_on
      assert source.documents.attached?
    end
  end

  test "the dates are date-only on the form and on the page" do
    with_orders(@world) do
      @source.update!(starts_on: "2026-09-01", ends_on: "2027-06-30", report_due_on: "2027-01-31", spent_outside_as_of: "2026-10-01")
      sign_in @world.admin.user

      get new_orders_funding_source_url
      %w[starts_on ends_on report_due_on spent_outside_as_of].each do |field|
        assert_select "input[type=date][name='funding_source[#{field}]']"
      end
      assert_select "input[type=datetime-local], input[type=datetime]", 0

      get edit_orders_funding_source_url(@source)
      assert_select "input[type=date][name='funding_source[starts_on]'][value='2026-09-01']"
      assert_select "input[type=date][name='funding_source[report_due_on]'][value='2027-01-31']"
      assert_select "input[type=date][name='funding_source[spent_outside_as_of]'][value='2026-10-01']"

      get orders_funding_source_url(@source)
      assert_match "September 01, 2026 to June 30, 2027", response.body
      assert_match "January 31, 2027", response.body
      assert_no_match(/\d{1,2}:\d{2}/, css_select("dl").text)
    end
  end

  test "saving a source keeps its documents, adds new ones and removes ticked ones" do
    with_orders(@world) do
      @source.documents.attach(io: StringIO.new("one"), filename: "one.txt")
      @source.documents.attach(io: StringIO.new("two"), filename: "two.txt")
      two = @source.documents.find { |document| document.filename.to_s == "two.txt" }
      sign_in @world.funding_manager.user

      patch orders_funding_source_url(@source), params: { funding_source: { name: "Typo fixed", documents: [ "" ] } }
      assert_equal %w[one.txt two.txt], @source.reload.documents.map { |document| document.filename.to_s }.sort

      patch orders_funding_source_url(@source), params: { funding_source: { documents: [ "", gift_letter ] }, remove_document_ids: [ two.id ] }
      names = @source.reload.documents.map { |document| document.filename.to_s }
      assert_includes names, "one.txt"
      assert_not_includes names, "two.txt"
      assert_equal 2, names.size
    end
  end

  test "a document ticked for removal stays when the save is refused" do
    with_orders(@world) do
      @source.documents.attach(io: StringIO.new("one"), filename: "one.txt")
      sign_in @world.funding_manager.user

      patch orders_funding_source_url(@source), params: { funding_source: { restriction: "" }, remove_document_ids: [ @source.documents.first.id ] }
      assert_response :unprocessable_entity
      assert_equal 1, @source.reload.documents.count
    end
  end

  test "the report CSV quotes a source name that looks like a formula" do
    with_orders(@world) do
      @source.update!(name: "=HYPERLINK(\"http://example.test\")")
      sign_in @world.funding_manager.user

      get report_orders_funding_source_url(@source, format: :csv)
      assert_equal "'=HYPERLINK(\"http://example.test\")", CSV.parse(response.body).first.first
    end
  end

  test "a source needs a restriction when it is restricted" do
    with_orders(@world) do
      sign_in @world.funding_manager.user

      assert_no_difference "FundingSource.count" do
        post orders_funding_sources_url, params: { funding_source: { team_id: @world.robotics.id, name: "Gift", kind: "restricted" } }
      end
      assert_response :unprocessable_entity
    end
  end

  test "a funding manager can't set up a source for a team outside their reach" do
    with_orders(@world, orders_funding_managers: "#{@world.funder_badge.name} > #{@world.robotics.name}") do
      sign_in @world.funding_manager.user

      assert_no_difference "FundingSource.count" do
        post orders_funding_sources_url, params: { funding_source: { team_id: @world.art.id, name: "Elsewhere", kind: "general" } }
      end
      assert_response :unprocessable_entity
    end
  end

  test "a funding manager can't move a source to a team outside their reach" do
    with_orders(@world, orders_funding_managers: "#{@world.funder_badge.name} > #{@world.robotics.name}") do
      sign_in @world.funding_manager.user

      patch orders_funding_source_url(@source), params: { funding_source: { team_id: @world.art.id } }
      assert_response :unprocessable_entity
      assert_equal @world.robotics, @source.reload.team
    end
  end

  test "a team manager can edit and an admin can delete an unused source" do
    with_orders(@world) do
      sign_in @world.manager.user
      patch orders_funding_source_url(@source), params: { funding_source: { name: "Renamed", active: "0" } }
      assert_redirected_to orders_funding_source_url(@source)
      assert_not @source.reload.active?

      sign_in @world.admin.user
      assert_difference "FundingSource.count", -1 do
        delete orders_funding_source_url(@source)
      end
    end
  end

  test "a source in use can't be deleted" do
    with_orders(@world) do
      submitted_request(@world, funding_source: @source)
      sign_in @world.admin.user

      assert_no_difference "FundingSource.count" do
        delete orders_funding_source_url(@source)
      end
      assert_match "can't be deleted", flash[:alert]
    end
  end

  test "the report lists bought lines with the approver and downloads as CSV" do
    with_orders(@world) do
      request = submitted_request(@world, lines: [ { description: "Motor", quantity: 2, price: 30 } ], funding_source: @source)
      request.decide!(:approved, by: @world.mentor, fits_restriction: true)
      buy(@world, request.order_lines, vendor: @world.preferred_vendor, shipping_cents: 500)
      sign_in @world.funding_manager.user

      get report_orders_funding_source_url(@source)
      assert_response :success
      assert_match "Motor", response.body
      assert_match "Mentor Example", response.body
      assert_match "$65.00", response.body

      get report_orders_funding_source_url(@source, format: :csv)
      assert_response :success
      assert_equal "text/csv", response.media_type
      rows = CSV.parse(response.body)
      assert_equal [ "Build Budget" ], rows.first
      assert_equal Orders::FundingReport::HEADERS, rows.second
      assert_equal [ "Motor", "2", "Parts Depot", request.display_title, "Mentor Example", "60.00", "5.00", "65.00" ], rows.third.values_at(1, 2, 3, 4, 5, 6, 7, 8)
      assert_equal "65.00", rows.last.last
    end
  end

  test "the delete refusal points at the In use box" do
    with_orders(@world) do
      submitted_request(@world, funding_source: @source)
      sign_in @world.admin.user
      delete orders_funding_source_url(@source)
      assert_match "Untick In use", flash[:alert]
    end
  end

  test "the report is refused to someone who can't see the numbers" do
    with_orders(@world) do
      sign_in @world.teammate.user
      get report_orders_funding_source_url(@source)
      assert_redirected_to root_url
      get report_orders_funding_source_url(@source, format: :csv)
      assert_redirected_to root_url
    end
  end
end
