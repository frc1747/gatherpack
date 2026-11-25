require "application_system_test_case"
require_relative "../support/accounting_rules_world"

# The Home account row on a phone: Pay online keeps its label, and the rule
# link opens the Account tab rather than the outside payment page.
class MyGatherpackAccountingSystemTest < ApplicationSystemTestCase
  include Devise::Test::IntegrationHelpers
  include AccountingRulesWorld

  # config.hosts allows localhost in test, but not Capybara's 127.0.0.1.
  setup do
    @saved_app_host = Capybara.app_host
    @saved_include_port = Capybara.always_include_port
    Capybara.app_host = "http://localhost"
    Capybara.always_include_port = true
    @restore_settings = SettingsTestHelper.apply(feature_my_gatherpack: "true", feature_accounting: "true")
    @nancy = create_rule_person("Nancy", "Davolio", customer: "58")
    add_charge("58", "I1", total: 40_000, balance: 5_000, label: "Invoice 1042 · Dues", pay_url: "https://pay.example.com/1042")
    @rule = create_rule(read_permission: "family", amount_permission: "family", show_pay_links: true)
    evaluate(@rule)
    page.driver.browser.manage.window.resize_to(390, 844)
  end

  teardown do
    page.driver.browser.manage.window.resize_to(1400, 1400)
    @restore_settings&.call
    Capybara.app_host = @saved_app_host
    Capybara.always_include_port = @saved_include_port
  end

  test "on a phone Pay online keeps its label and the rule link opens the Account tab" do
    sign_in @nancy.user
    visit root_path

    within "[data-home-section=accounting]" do
      pay = find("a", text: "Pay online")
      assert pay.visible?
      assert_operator pay.evaluate_script("this.getBoundingClientRect().height"), :>=, 44

      link = find("a", text: "2027 Membership Dues")
      hit = link.evaluate_script(<<~JS)
        (() => { const box = this.getClientRects()[0];
                 const hit = document.elementFromPoint(box.left + box.width / 2, box.top + box.height / 2);
                 return this.contains(hit); })()
      JS
      assert hit, "the rule link is covered by another element"
      link.click
    end

    assert_current_path person_accounting_path(@nancy)
  end
end
