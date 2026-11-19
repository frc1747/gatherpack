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

  # Fills a grant field's blank row (the last) with a row.
  def add_row(params, field, **row)
    rows = params["settings"][field]["rows"]
    rows[rows.keys.map(&:to_i).max.to_s].merge!(row.transform_keys(&:to_s))
  end

  def add_grant(params, field, badge, team = @world.club)
    add_row(params, field, kind: "badge", badge: badge.name, team: team.name)
  end

  test "only admins see and change the setup" do
    with_orders(@world) do
      before = Settings[:orders_buyers]
      [ @world.manager, @world.buyer, @world.mentor, @world.requester ].each do |person|
        sign_in person.user
        get orders_settings_url
        assert_redirected_to root_url
        patch orders_settings_url, params: { settings: { buyers: "" } }
        assert_redirected_to root_url
      end
      assert_equal before, Settings[:orders_buyers]
    end
  end

  test "the page shows every orders setting, in groups" do
    with_orders(@world) do
      sign_in @world.admin.user
      get orders_settings_url
      assert_select "h1", "Orders setup"
      assert_equal [ "Who can ask", "Who sees every request", "Lists", "Who buys", "Who manages funding sources",
        "Seeing requests", "Buying", "Funding", "Closing", "Email" ], css_select("h2").map { |node| node.text.squish }
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

  test "Order Notices offers the four choices, defaults to the daily digest and saves" do
    with_orders(@world) do
      sign_in @world.admin.user
      get orders_settings_url
      assert_select "label[for=values_orders_notices]", "Order Notices"
      assert_equal [ "An email each time", "In the daily digest", "In the Weekly Infodump", "Off" ],
        css_select("select[name='values[orders_notices]'] option").map(&:text)
      assert_select "select[name='values[orders_notices]'] option[selected][value=daily]"
      assert_select ".form-text", /How people hear about requests: approvers about requests waiting for them/

      params = open_form
      params["values"]["orders_notices"] = "each"
      patch orders_settings_url, params: params
      assert_redirected_to orders_settings_url
      assert_equal :each, Orders::Config.notices

      params["values"]["orders_notices"] = "hourly"
      patch orders_settings_url, params: params
      assert_response :unprocessable_entity
      assert_match "Order Notices: choose one of the options.", response.body
      assert_equal :each, Orders::Config.notices
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
      params["settings"]["funding_managers"]["rows"].each_value { |row| row["remove"] = "1" if row["line"].present? }
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
      assert_select "section:not([data-controller]) select[name^='values'], section:not([data-controller]) input[name^='values']", minimum: 6
    end
  end

  test "bad yes-no, number and tolerance values are refused and nothing is saved" do
    with_orders(@world) do
      sign_in @world.admin.user
      params = open_form
      params["values"].merge!("orders_team_can_see" => "maybe", "orders_close_after_days" => "soon", "orders_price_tolerance" => { "percent" => "ten", "amount" => "" })
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

    with_orders(@world, orders_requesters: @world.robotics.name, orders_viewers: @world.art.name) do
      sign_in @world.admin.user
      get orders_settings_url

      assert_select "input[type=checkbox][name='settings[requesters][values][]'][value='#{@world.robotics.name}'][checked]"
      assert_select "input[type=checkbox][name='settings[requesters][values][]'][value='#{@world.art.name}']:not([checked])"
      assert_select "input[type=checkbox][name='settings[viewers][values][]'][value='#{@world.art.name}'][checked]"
      assert_select "input[type=checkbox][name='settings[viewers][values][]'][value='#{@world.robotics.name}']:not([checked])"
    end
  end

  test "without the pickers the team lists are text boxes with the saved lines" do
    skip "the settings pickers draw these" if pickers?

    with_orders(@world, orders_requesters: @world.robotics.name, orders_viewers: @world.art.name) do
      sign_in @world.admin.user
      get orders_settings_url
      assert_select "textarea[name='settings[requesters]']", text: @world.robotics.name
      assert_select "textarea[name='settings[viewers]']", text: @world.art.name
      assert_select ".form-text", /One team name per line\. Or a row as for who buys/
    end
  end

  test "who buys and who manages funding sources are drawn as grant rows, one per saved line" do
    buyers = [ grant(@world.buyer_badge, @world.robotics), "Managers of #{@world.club.name} > #{@world.art.name}",
      "Managers of #{@world.robotics.name}", Orders::Reach::OWN_TEAM_LINE ].join("\n")
    with_orders(@world, orders_buyers: buyers) do
      sign_in @world.admin.user
      get orders_settings_url

      assert_select "[data-controller=orders-grant-rows]", 2
      assert_select "p", text: "Any of these:", minimum: 2
      assert_select ".form-text", "Add who buys, for example holders of a Buyer badge. Admins always can."
      assert_select "select[name='settings[buyers][rows][0][kind]'] option[selected][value=badge]", "A badge"
      assert_select "select[name='settings[buyers][rows][0][badge]'] option[selected]", @world.buyer_badge.name
      assert_select "select[name='settings[buyers][rows][0][team]'] option[selected][value='#{@world.robotics.name}']", "For: #{@world.robotics.name}"
      assert_select "select[name='settings[buyers][rows][1][kind]'] option[selected][value=team_managers]", "Managers of a team"
      assert_select "select[name='settings[buyers][rows][1][manager_team]'] option[selected]", @world.club.name
      assert_select "select[name='settings[buyers][rows][1][team]'] option[selected][value='#{@world.art.name}']"
      assert_select "select[name='settings[buyers][rows][2][team]'] option[selected]", 0
      assert_select "select[name='settings[buyers][rows][3][kind]'] option[selected][value=own_team_managers]", "Managers of the request's own team"
      assert_select "[data-for-kind='badge team_managers'] select[name='settings[buyers][rows][4][team]'] option[value='']", "For: every team"
      assert_select "input[type=checkbox][name='settings[buyers][rows][3][remove]']"
      assert_select "input[name='settings[buyers][rows][4][remove]']", 0

      patch orders_settings_url, params: open_form
      assert_redirected_to orders_settings_url
      assert_equal buyers, Settings[:orders_buyers]
    end
  end

  test "each kind of grant row is saved in the format Orders::Reach reads" do
    with_orders(@world, orders_buyers: "", orders_funding_managers: "") do
      sign_in @world.admin.user
      [ [ { kind: "badge", badge: @world.buyer_badge.name, team: "" }, @world.buyer_badge.name ],
        [ { kind: "team_managers", manager_team: @world.club.name, team: @world.art.name }, "Managers of #{@world.club.name} > #{@world.art.name}" ],
        [ { kind: "own_team_managers", badge: @world.buyer_badge.name, team: @world.art.name }, Orders::Reach::OWN_TEAM_LINE ] ].each do |row, line|
        params = open_form
        params["settings"]["buyers"]["rows"].each_value { |each| each["remove"] = "1" if each["line"].present? }
        add_row(params, "buyers", **row)
        patch orders_settings_url, params: params
        assert_redirected_to orders_settings_url
        assert_equal line, Settings[:orders_buyers]
      end

      params = open_form
      add_row(params, "funding_managers", kind: "team_managers", manager_team: "", team: "")
      patch orders_settings_url, params: params
      assert_equal "", Settings[:orders_funding_managers], "a row with no team is left out"
    end
  end

  test "a managers row naming a team that doesn't exist is refused" do
    with_orders(@world) do
      sign_in @world.admin.user
      before = Settings[:orders_buyers]
      params = open_form
      add_row(params, "buyers", kind: "team_managers", manager_team: "Atlantis")
      patch orders_settings_url, params: params

      assert_response :unprocessable_entity
      assert_match "Who buys: no team named &quot;Atlantis&quot;.", response.body
      assert_equal before, Settings[:orders_buyers]
    end
  end

  test "who can ask takes badge and managers rows as well as teams" do
    skip "the settings pickers draw who can ask" if pickers?

    with_orders(@world) do
      sign_in @world.admin.user
      params = open_form
      params["settings"]["requesters"] = [ @world.robotics.name, @world.buyer_badge.name, "Managers of #{@world.art.name}" ].join("\n")
      patch orders_settings_url, params: params
      assert_redirected_to orders_settings_url

      params = open_form
      params["settings"]["requesters"] = "Nobody Here"
      patch orders_settings_url, params: params
      assert_response :unprocessable_entity
      assert_match "Who can ask: no team or badge named &quot;Nobody Here&quot;.", response.body
    end
  end

  test "saving the form unchanged leaves every setting's text as it was" do
    with_orders(@world, orders_requesters: "#{@world.robotics.name}\r\n#{@world.art.name}", orders_viewers: "#{@world.club.name}\r\n",
      orders_buyers: "#{@world.buyer_badge.name}>#{@world.club.name}\r\nmanagers of #{@world.club.name}\r\nmanagers of each team",
      orders_price_tolerance: "5%, 10") do
      sign_in @world.admin.user
      before = %i[orders_requesters orders_viewers orders_buyers orders_price_tolerance].index_with { |key| Settings[key] }

      patch orders_settings_url, params: open_form
      assert_redirected_to orders_settings_url

      before.each { |key, value| assert_equal value, Settings[key], "#{key} changed" }
    end
  end

  test "saving the default setup unchanged keeps the defaults" do
    with_settings(feature_orders: "true") do
      sign_in @world.admin.user
      before = %i[orders_requesters orders_viewers orders_buyers].index_with { |key| Settings[key] }

      patch orders_settings_url, params: open_form
      assert_redirected_to orders_settings_url

      before.each { |key, value| assert_equal value, Settings[key], "#{key} changed" }
      assert_equal [ "approval" ], Orders::Config.approval_steps.map(&:key)
    end
  end

  test "who can ask, who sees every request and who buys are saved in the formats the app reads" do
    with_orders(@world) do
      sign_in @world.admin.user
      params = open_form
      if pickers?
        params["settings"]["requesters"]["values"] = [ "", @world.robotics.name ]
        params["settings"]["viewers"]["values"] = [ "", @world.club.name, @world.art.name ]
      else
        params["settings"]["requesters"] = @world.robotics.name
        params["settings"]["viewers"] = "#{@world.club.name}\n#{@world.art.name}"
      end
      params["settings"]["buyers"]["rows"].each_value { |row| row["remove"] = "1" if row["line"].present? }
      add_grant(params, "buyers", @world.funder_badge, @world.robotics)
      patch orders_settings_url, params: params
      assert_redirected_to orders_settings_url

      assert_equal [ @world.robotics ], Orders::Config.requester_teams
      assert_equal [ @world.art, @world.club ].map(&:name).sort, Orders::Config.viewer_teams.map(&:name).sort
      assert_equal 2, Settings[:orders_viewers].lines.size
      assert_equal grant(@world.funder_badge, @world.robotics), Settings[:orders_buyers]
    end
  end

  test "saving the page unchanged keeps settings that differ from the defaults" do
    with_orders(@world, orders_price_tolerance: "3%, 7", orders_close_after_days: "30", orders_team_can_see: "false") do
      sign_in @world.admin.user
      patch orders_settings_url, params: open_form

      assert_equal "3%, 7", Settings[:orders_price_tolerance]
      assert_equal 30, Orders::Config.close_after_days
      assert_not Orders::Config.team_can_see?
      assert_equal "#{grant(@world.funder_badge)}\n#{Orders::Reach::OWN_TEAM_LINE}", Settings[:orders_funding_managers]
    end
  end

  test "bad input is refused and nothing is saved" do
    with_orders(@world) do
      sign_in @world.admin.user
      before = %i[orders_buyers orders_close_after_days].index_with { |key| Settings[key] }

      params = open_form
      params["values"]["orders_close_after_days"] = "30"
      add_grant(params, "buyers", Struct.new(:name).new("No Such Badge"))
      patch orders_settings_url, params: params

      assert_response :unprocessable_entity
      assert_match "no badge named", response.body
      before.each { |key, value| assert_equal value, Settings[key] }
    end
  end

  test "a saved grant whose badge is gone doesn't block saving" do
    with_orders(@world, orders_buyers: "Retired Badge\n#{grant(@world.buyer_badge)}") do
      sign_in @world.admin.user
      params = open_form
      params["values"]["orders_close_after_days"] = "20"
      patch orders_settings_url, params: params
      assert_redirected_to orders_settings_url
      assert_equal 20, Orders::Config.close_after_days
      assert_equal "Retired Badge\n#{grant(@world.buyer_badge)}", Settings[:orders_buyers]
    end
  end

  test "Orders setup is a button on the main Setup page, for admins only, and not in the menu" do
    with_orders(@world) do
      sign_in @world.admin.user
      get setup_url
      assert_select "a.btn[href='#{orders_settings_path}']", "Orders"
      assert_select "h2, h3, h4, h5", text: "Orders and Inventory"
      assert_select "a.btn[href='#{orders_approval_steps_path}']", "Approval Steps"
      assert_select "a.btn[href='#{managed_list_path(:payment_methods)}']", "Payment Methods"
      assert_select "a.btn[href='#{managed_list_path(:delivery_problem_kinds)}']", "Delivery Problems"
      headings = css_select("h5.text-muted").map { |node| node.text.squish }
      positions = headings.map { |heading| GatherPack::Features.sections[heading]&.position || Float::INFINITY }
      assert_equal 35, GatherPack::Features.sections["Orders and Inventory"]&.position
      assert_equal positions.sort, positions, "Setup headings in position order: #{headings.inspect}"
      assert_operator positions[headings.index("Orders and Inventory")], :<, Float::INFINITY
      get orders_reports_url
      assert_select "a[href='#{orders_settings_path}']", 0

      [ @world.manager, @world.buyer, @world.requester ].each do |person|
        sign_in person.user
        get orders_requests_url
        assert_select "a[href='#{orders_settings_path}']", 0
      end
    end
  end

  test "Orders setup links to the approval steps, payment methods and delivery problems" do
    with_orders(@world) do
      sign_in @world.admin.user
      get orders_settings_url
      assert_select "#orders_lists a[href='#{orders_approval_steps_path}']", /Approval steps/
      assert_select "#orders_lists a[href='#{managed_list_path(:payment_methods)}']", /Payment methods/
      assert_select "#orders_lists a[href='#{managed_list_path(:delivery_problem_kinds)}']", /Delivery problems/
      assert_select "[name^='paid_with'], [name='large_amount'], [name^='settings[approvers]']", 0
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
