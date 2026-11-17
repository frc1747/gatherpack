require "test_helper"
require "support/orders_world"

class Orders::SettingsControllerTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers
  include OrdersWorld

  setup { @world = build_orders_world }

  # What the page's form would post as drawn: every field with its value,
  # checked boxes only, the selected option of each select, and nothing
  # from the add-a-row templates.
  def form_params
    form = Nokogiri::HTML5(response.body).at_css("form[action='#{orders_settings_path}']")
    pairs = form.css("input, select, textarea").filter_map do |node|
      next if node.ancestors("template").any? || node["name"].blank? || node["disabled"]

      case node.name
      when "select"
        option = node.at_css("option[selected]") || node.at_css("option")
        [ node["name"], option ? option["value"].to_s : "" ]
      when "textarea"
        [ node["name"], node.text.delete_prefix("\n") ]
      else
        next if node["type"] == "submit"
        next if %w[checkbox radio].include?(node["type"]) && !node.key?("checked")

        [ node["name"], node["value"].to_s ]
      end
    end
    Rack::Utils.parse_nested_query(URI.encode_www_form(pairs))
  end

  def open_form
    get orders_settings_url
    assert_response :success
    form_params
  end

  def grant(badge, team = @world.club)
    "#{badge.name} > #{team.name}"
  end

  def pickers?
    Orders::SettingsEditor.pickers?
  end

  # Puts one new badge grant in a field's blank row (or its text box).
  def add_grant(params, field, badge, team = @world.club)
    if pickers?
      rows = params["settings"][field]["rows"] ||= {}
      index = (rows.keys.map(&:to_i).max || -1).to_s
      rows[index] ||= {}
      rows[index].merge!("badge" => badge.name, "team" => team.name)
    else
      params["settings"][field] = [ params["settings"][field], grant(badge, team) ].compact_blank.join("\n")
    end
  end

  test "only admins see and change the setup" do
    with_orders(@world) do
      before = Settings[:orders_approval_steps]
      [ @world.manager, @world.buyer, @world.mentor, @world.requester ].each do |person|
        sign_in person.user
        get orders_settings_url
        assert_redirected_to root_url
        patch orders_settings_url, params: { large_amount: "100", paid_with: { "0" => { label: "Cash" } } }
        assert_redirected_to root_url
      end
      assert_equal before, Settings[:orders_approval_steps]
    end
  end

  test "the page shows every orders setting, in groups" do
    with_orders(@world) do
      sign_in @world.admin.user
      get orders_settings_url
      assert_select "h1", "Orders setup"
      assert_equal [ "Who can ask", "Who sees every request", "Who approves", "Over $ , also needs", "Who buys", "Who manages funding sources",
        "Paid with", "Seeing requests", "Buying", "Funding", "Closing" ], css_select("h2").map { |node| node.text.squish }
      assert_select "select[name='values[orders_team_can_see]'] option[selected][value=true]", "Yes"
      assert_select "input[type=number][name='values[orders_price_tolerance][percent]'][value='10']"
      assert_select "input[type=number][name='values[orders_price_tolerance][amount]'][value='25']"
      assert_select "label[for=values_orders_price_tolerance_percent]", "Up to"
      assert_select "label[for=values_orders_price_tolerance_amount]", "or up to $"
      assert_select "input[type=text][name*=tolerance]", 0
      assert_select "input[type=number][name='values[orders_close_after_days]'][value='14']"
      assert_select "select[name='values[orders_require_funding_source]'] option[selected][value=false]", "No"
      assert_select ".form-text", /Received requests close after this many days/
    end
  end

  test "every setting registered in the Orders group is on the page and saves" do
    with_orders(@world) do
      sign_in @world.admin.user
      get orders_settings_url
      shown = Orders::SettingsEditor.section_keys + Orders::SettingsEditor::FIELD_SETTINGS
      assert_equal Settings.settings("Orders").map(&:setting_key).sort, shown.sort
      Orders::SettingsEditor.section_keys.each { |key| assert_select "[name^='values[#{key}]']", minimum: 1, message: "#{key} isn't on the page" }

      params = open_form
      params["values"].merge!("orders_team_can_see" => "false", "orders_price_tolerance" => { "percent" => "5", "amount" => "40" }, "orders_require_other_vendor_reason" => "true",
        "orders_require_funding_source" => "true", "orders_requesters_pick_funding" => "true", "orders_close_after_days" => "30")
      patch orders_settings_url, params: params
      assert_redirected_to orders_settings_url

      assert_not Orders::Config.team_can_see?
      assert_equal "5%, 40", Settings[:orders_price_tolerance]
      assert_equal [ BigDecimal("5"), 4000 ], [ Orders::Config.price_tolerance.percent, Orders::Config.price_tolerance.amount_cents ]
      assert_equal 30, Orders::Config.close_after_days
      assert Settings[:orders_require_other_vendor_reason]
      assert Settings[:orders_require_funding_source]
      assert Settings[:orders_requesters_pick_funding]
    end
  end

  test "an orders setting that isn't listed is drawn under more settings" do
    with_orders(@world) do
      Settings.register(:orders_test_extra, :integer, "Extra Limit", "3", "Orders", "A made-up setting")
      sign_in @world.admin.user
      get orders_settings_url
      assert_select "h2", "More settings"
      assert_select "input[type=number][name='values[orders_test_extra]'][value='3']"

      params = open_form
      params["values"]["orders_test_extra"] = "9"
      patch orders_settings_url, params: params
      assert_equal "9", Settings.get(:orders_test_extra).value
    ensure
      Settings.instance.settings.delete(:orders_test_extra)
    end
  end

  test "price tolerance round trips as the text the app parses, with either number blank" do
    with_orders(@world) do
      sign_in @world.admin.user
      { [ "10", "25" ] => "10%, 25", [ "10", "" ] => "10%", [ "", "25" ] => "25", [ "2.5", "0" ] => "2.5%, 0", [ "", "" ] => "" }.each do |(percent, amount), text|
        params = open_form
        params["values"]["orders_price_tolerance"] = { "percent" => percent, "amount" => amount }
        patch orders_settings_url, params: params
        assert_redirected_to orders_settings_url
        assert_equal text, Settings[:orders_price_tolerance]

        get orders_settings_url
        field = Orders::PriceToleranceField.new(text)
        assert_select "input[name='values[orders_price_tolerance][percent]'][value='#{field.percent}']", field.percent ? 1 : 0
        assert_select "input[name='values[orders_price_tolerance][amount]'][value='#{field.amount}']", field.amount ? 1 : 0
      end
    end
  end

  test "a saved tolerance that isn't a percentage and an amount shows as not found and is kept" do
    with_orders(@world, orders_price_tolerance: "about ten percent") do
      sign_in @world.admin.user
      get orders_settings_url
      assert_select "fieldset .text-danger", "Not found: about ten percent"

      patch orders_settings_url, params: open_form
      assert_redirected_to orders_settings_url
      assert_equal "about ten percent", Settings[:orders_price_tolerance]

      params = open_form
      params["values"]["orders_price_tolerance"].merge!("percent" => "8")
      patch orders_settings_url, params: params
      assert_equal "8%", Settings[:orders_price_tolerance]
    end
  end

  test "who manages funding sources is saved in the format the app reads" do
    with_orders(@world) do
      sign_in @world.admin.user
      params = open_form
      if pickers?
        params["settings"]["funding_managers"]["rows"]["0"]["remove"] = "1"
      else
        params["settings"]["funding_managers"] = ""
      end
      add_grant(params, "funding_managers", @world.buyer_badge, @world.robotics)
      patch orders_settings_url, params: params
      assert_redirected_to orders_settings_url
      assert_equal grant(@world.buyer_badge, @world.robotics), Settings[:orders_funding_managers]
    end
  end

  test "the setup page works without JavaScript: every field is a plain form control" do
    with_orders(@world) do
      sign_in @world.admin.user
      get orders_settings_url
      assert_select "form[action='#{orders_settings_path}'] input[type=submit][value=Save]"
      assert_select "template", minimum: 1
      assert_select "[hidden]", minimum: 1 # only the add buttons, shown by script
      assert_select "section:not([data-controller]) select[name^='values'], section:not([data-controller]) input[name^='values']", minimum: 6
    end
  end

  test "bad yes-no, number and tolerance values are refused and nothing is saved" do
    with_orders(@world) do
      sign_in @world.admin.user
      params = open_form
      params["values"].merge!("orders_team_can_see" => "maybe", "orders_close_after_days" => "soon", "orders_price_tolerance" => { "percent" => "ten", "amount" => "" })
      params["large_amount"] = "100"
      patch orders_settings_url, params: params
      assert_response :unprocessable_entity
      assert_match "choose yes or no", response.body
      assert_match "must be a whole number", response.body
      assert_match "use numbers for the percentage and the amount", response.body
      assert_equal "10%, 25", Settings[:orders_price_tolerance]
      assert_equal 1, Orders::Config.approval_steps.size
    end
  end

  test "each picker shows the saved values" do
    skip "needs the settings pickers" unless pickers?

    with_orders(@world, orders_requesters: @world.robotics.name, orders_viewers: @world.art.name,
      orders_buyers: grant(@world.buyer_badge, @world.robotics),
      orders_paid_with: JSON.generate([ { "label" => "Team card", "reimburse" => false }, { "label" => "Own money", "reimburse" => true } ]),
      orders_approval_steps: JSON.generate([
        { "key" => "mentor", "name" => "Mentor", "minimum" => 0, "approvers" => [ grant(@world.approver_badge) ] },
        { "key" => "treasurer", "name" => "Treasurer", "minimum" => 500, "approvers" => [ grant(@world.funder_badge, @world.robotics) ] }
      ])) do
      sign_in @world.admin.user
      get orders_settings_url

      assert_select "input[type=checkbox][name='settings[requesters][values][]'][value='#{@world.robotics.name}'][checked]"
      assert_select "input[type=checkbox][name='settings[requesters][values][]'][value='#{@world.art.name}']:not([checked])"
      assert_select "input[type=checkbox][name='settings[viewers][values][]'][value='#{@world.art.name}'][checked]"
      assert_select "input[type=checkbox][name='settings[viewers][values][]'][value='#{@world.robotics.name}']:not([checked])"
      assert_select "select[name='settings[approvers][rows][0][badge]'] option[selected]", @world.approver_badge.name
      assert_select "select[name='settings[approvers][rows][0][team]'] option[selected][value='#{@world.club.name}']",
        "Up to: #{@world.club.name}"
      assert_select "select[name='settings[approvers][rows][1][team]'] option[value='']", "Up to: every team"
      assert_select "select[name$='[team]'] option[value='']", text: "Up to: every team", minimum: 3
      assert_select "fieldset .form-text", /works up to the team picked, and the teams below it\. No team: every team\./
      assert_select "input[name=large_amount][value='500']"
      assert_select "select[name='settings[large_approvers][rows][0][badge]'] option[selected]", @world.funder_badge.name
      assert_select "select[name='settings[large_approvers][rows][0][team]'] option[selected][value='#{@world.robotics.name}']"
      assert_select "select[name='settings[buyers][rows][0][badge]'] option[selected]", @world.buyer_badge.name
      assert_select "input[name='paid_with[1][label]'][value='Own money']"
      assert_select "input[type=checkbox][name='paid_with[1][reimburse]'][checked]"
      assert_select "input[type=checkbox][name='paid_with[0][reimburse]']:not([checked])"
      assert_select "#current_steps", 0
    end
  end

  test "without the pickers each field is a text box with the saved lines" do
    skip "the settings pickers draw these" if pickers?

    with_orders(@world, orders_requesters: @world.robotics.name, orders_viewers: @world.art.name) do
      sign_in @world.admin.user
      get orders_settings_url
      assert_select "textarea[name='settings[requesters]']", text: @world.robotics.name
      assert_select "textarea[name='settings[viewers]']", text: @world.art.name
      assert_select "textarea[name='settings[approvers]']", text: grant(@world.approver_badge)
      assert_select "textarea[name='settings[buyers]']", text: grant(@world.buyer_badge)
      assert_select "input[name=large_amount][value='']"
      assert_select ".form-text", /the badge works for that team and the teams below it\. Badge name alone: every team\./
    end
  end

  test "saving the form unchanged leaves every setting's text as it was" do
    steps = "[{\"key\":\"mentor\",\"name\":\"Mentor\",\"minimum\":0,\"approvers\":[\"#{grant(@world.approver_badge)}\"]}," \
      "{\"key\":\"treasurer\",\"name\":\"Treasurer\",\"minimum\":250.5,\"approvers\":[]}]"
    paid_with = JSON.generate([ { "label" => "Team card", "reimburse" => false }, { "label" => "Own money", "reimburse" => true } ])
    with_orders(@world, orders_approval_steps: steps, orders_paid_with: paid_with,
      orders_requesters: "#{@world.robotics.name}\r\n#{@world.art.name}", orders_viewers: "#{@world.club.name}\r\n",
      orders_buyers: "#{@world.buyer_badge.name}>#{@world.club.name}",
      orders_price_tolerance: "5%, 10") do
      sign_in @world.admin.user
      before = %i[orders_approval_steps orders_paid_with orders_requesters orders_viewers orders_buyers orders_price_tolerance].index_with { |key| Settings[key] }

      patch orders_settings_url, params: open_form
      assert_redirected_to orders_settings_url

      before.each { |key, value| assert_equal value, Settings[key], "#{key} changed" }
    end
  end

  test "saving the default setup unchanged keeps the defaults" do
    with_settings(feature_orders: "true") do
      sign_in @world.admin.user
      before = %i[orders_approval_steps orders_paid_with orders_requesters orders_viewers orders_buyers].index_with { |key| Settings[key] }

      patch orders_settings_url, params: open_form
      assert_redirected_to orders_settings_url

      before.each { |key, value| assert_equal value, Settings[key], "#{key} changed" }
      assert_equal [ "approval" ], Orders::Config.approval_steps.map(&:key)
    end
  end

  test "an amount adds a second approval and clearing it removes it" do
    with_orders(@world) do
      sign_in @world.admin.user

      params = open_form
      params["large_amount"] = "$1,000"
      add_grant(params, "large_approvers", @world.funder_badge)
      patch orders_settings_url, params: params
      assert_redirected_to orders_settings_url

      first, second = Orders::Config.approval_steps
      assert_equal [ "approval", "Approval", 0, [ grant(@world.approver_badge) ] ], [ first.key, first.name, first.minimum_cents, first.approvers ]
      assert_equal [ "large_purchase", "Large purchase", 100_000, [ grant(@world.funder_badge) ] ], [ second.key, second.name, second.minimum_cents, second.approvers ]
      assert_equal 1000, JSON.parse(Settings[:orders_approval_steps]).second["minimum"]

      params = open_form
      assert_equal "1000", params["large_amount"]
      params["large_amount"] = ""
      patch orders_settings_url, params: params
      assert_redirected_to orders_settings_url
      assert_equal [ "approval" ], Orders::Config.approval_steps.map(&:key)
    end
  end

  test "a second approval added again never takes the key of a removed one that has approvals" do
    with_orders(@world, **two_step_settings(@world)) do
      OrderApproval.create!(order_request: submitted_request(@world), step_key: "large_purchase", approver: @world.mentor, decision: :approved)
      sign_in @world.admin.user

      params = open_form
      params["large_amount"] = ""
      patch orders_settings_url, params: params
      assert_equal [ "mentor" ], Orders::Config.approval_steps.map(&:key)

      params = open_form
      params["large_amount"] = "300"
      patch orders_settings_url, params: params
      assert_equal %w[mentor large_purchase_2], Orders::Config.approval_steps.map(&:key)
    end
  end

  test "an existing second approval keeps its key and name when its amount changes" do
    with_orders(@world, **two_step_settings(@world, minimum: 500)) do
      sign_in @world.admin.user
      params = open_form
      params["large_amount"] = "750.25"
      patch orders_settings_url, params: params

      assert_equal [ [ "mentor", "Mentor", 0 ], [ "treasurer", "Treasurer", 75_025 ] ],
        Orders::Config.approval_steps.map { |step| [ step.key, step.name, step.minimum_cents ] }
    end
  end

  test "steps the page can't show are listed read-only, and saving replaces them" do
    with_orders(@world, orders_approval_steps: JSON.generate([
      { "key" => "mentor", "name" => "Mentor", "minimum" => 0, "approvers" => [ grant(@world.approver_badge) ] },
      { "key" => "coach", "name" => "Coach", "minimum" => 100, "approvers" => [] },
      { "key" => "treasurer", "name" => "Treasurer", "minimum" => 500, "approvers" => [ grant(@world.funder_badge) ] }
    ])) do
      sign_in @world.admin.user
      get orders_settings_url

      assert_select "#current_steps li", 3
      assert_select "#current_steps li", /Mentor:\s+every request, approved by team managers, #{Regexp.escape(grant(@world.approver_badge))}/
      assert_select "#current_steps li", /Coach:\s+requests of \$100\.00 or more, approved by team managers\./
      assert_select "#current_steps li", /Treasurer:\s+requests of \$500\.00 or more/
      assert_select "#current_steps", /Saving this page replaces these steps/

      patch orders_settings_url, params: form_params
      assert_redirected_to orders_settings_url
      assert_equal [ [ "mentor", 0 ], [ "coach", 10_000 ] ], Orders::Config.approval_steps.map { |step| [ step.key, step.minimum_cents ] }

      get orders_settings_url
      assert_select "#current_steps", 0
    end
  end

  test "a first step with a minimum is listed read-only" do
    with_orders(@world, orders_approval_steps: JSON.generate([ { "key" => "approval", "name" => "Approval", "minimum" => 50, "approvers" => [] } ])) do
      sign_in @world.admin.user
      get orders_settings_url
      assert_select "#current_steps li", 1
    end
  end

  test "who can ask, who sees every request, who buys and paid with are saved in the formats the app reads" do
    with_orders(@world) do
      sign_in @world.admin.user
      params = open_form
      if pickers?
        params["settings"]["requesters"]["values"] = [ "", @world.robotics.name ]
        params["settings"]["viewers"]["values"] = [ "", @world.club.name, @world.art.name ]
        params["settings"]["buyers"]["rows"]["0"]["remove"] = "1"
      else
        params["settings"]["requesters"] = @world.robotics.name
        params["settings"]["viewers"] = "#{@world.club.name}\n#{@world.art.name}"
        params["settings"]["buyers"] = ""
      end
      add_grant(params, "buyers", @world.funder_badge, @world.robotics)
      params["paid_with"]["0"]["remove"] = "1"
      params["paid_with"]["2"] = { "label" => "Cash", "reimburse" => "1" }
      patch orders_settings_url, params: params
      assert_redirected_to orders_settings_url

      assert_equal [ @world.robotics ], Orders::Config.requester_teams
      assert_equal [ @world.art, @world.club ].map(&:name).sort, Orders::Config.viewer_teams.map(&:name).sort
      assert_equal 2, Settings[:orders_viewers].lines.size
      assert_equal grant(@world.funder_badge, @world.robotics), Settings[:orders_buyers]
      assert_equal [ [ "Personal card — reimburse", true ], [ "Cash", true ] ], Orders::Config.paid_with.map { |choice| [ choice.label, choice.reimburse ] }
    end
  end

  test "saving the page unchanged keeps settings that differ from the defaults" do
    with_orders(@world, orders_price_tolerance: "3%, 7", orders_close_after_days: "30", orders_team_can_see: "false") do
      sign_in @world.admin.user
      patch orders_settings_url, params: open_form

      assert_equal "3%, 7", Settings[:orders_price_tolerance]
      assert_equal 30, Orders::Config.close_after_days
      assert_not Orders::Config.team_can_see?
      assert_equal grant(@world.funder_badge), Settings[:orders_funding_managers]
    end
  end

  test "bad input is refused and nothing is saved" do
    with_orders(@world) do
      sign_in @world.admin.user
      before = %i[orders_approval_steps orders_buyers orders_paid_with].index_with { |key| Settings[key] }

      params = open_form
      params["large_amount"] = "lots"
      add_grant(params, "buyers", Struct.new(:name).new("No Such Badge"))
      params["paid_with"]["0"]["label"] = "Changed"
      patch orders_settings_url, params: params

      assert_response :unprocessable_entity
      assert_match "must be a number of dollars above zero", response.body
      assert_match "no badge named", response.body
      before.each { |key, value| assert_equal value, Settings[key] }
    end
  end

  test "at least one way to pay is kept" do
    with_orders(@world) do
      sign_in @world.admin.user
      params = open_form
      params["paid_with"].each_value { |row| row["remove"] = "1" }
      patch orders_settings_url, params: params
      assert_response :unprocessable_entity
      assert_match "at least one way", response.body
    end
  end

  test "a saved grant whose badge is gone doesn't block saving" do
    with_orders(@world, orders_buyers: "Retired Badge\n#{grant(@world.buyer_badge)}") do
      sign_in @world.admin.user
      params = open_form
      params["large_amount"] = "100"
      patch orders_settings_url, params: params
      assert_redirected_to orders_settings_url
      assert_equal "Retired Badge\n#{grant(@world.buyer_badge)}", Settings[:orders_buyers]
    end
  end

  test "Orders setup is a button on the main Setup page, for admins only, and not in the menu" do
    with_orders(@world) do
      sign_in @world.admin.user
      get setup_url
      assert_select "a.btn[href='#{orders_settings_path}']", "Orders"
      get orders_reports_url
      assert_select "a[href='#{orders_settings_path}']", 0

      [ @world.manager, @world.buyer, @world.requester ].each do |person|
        sign_in person.user
        get orders_requests_url
        assert_select "a[href='#{orders_settings_path}']", 0
      end
    end
  end

  test "the settings page links to Orders setup while orders is on" do
    skip "needs Settings.page" unless Settings.respond_to?(:page)

    with_orders(@world) do
      sign_in @world.admin.user
      get settings_url
      assert_select "a[href='#{orders_settings_path}']", "Orders setup"
    end
  end
end
