require "test_helper"

class EmailNoticesControllerTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers

  setup do
    host! "localhost"
    @path = Rails.root.join("tmp", "settings-email-notices-test-#{Process.pid}.pstore").to_s
    File.delete(@path) if File.exist?(@path)
    @original_store = Settings.instance.store
    Settings.instance.store = PStore.new(@path, true)
    Settings[:feature_digests] = "true"

    GatherPack::Digests.register(:test_tasks, label: "Tasks", delivery: -> { :daily }, build: ->(*) { })
    GatherPack::Digests.register(:test_news, label: "News", delivery: -> { :weekly }, build: ->(*) { })
    GatherPack::Digests.register(:test_site, label: "Site only", delivery: -> { :daily }, build: ->(*) { }, personal: false)

    @alice = people(:one)
    sign_in @alice.user

    # These cover the choices' own page; where the Notifications page takes
    # cards, set the card aside so this build behaves like Summaries alone.
    @card = GatherPack::NotificationSections.unregister(:email_notices) if defined?(GatherPack::NotificationSections)
  end

  teardown do
    GatherPack::NotificationSections.registered[:email_notices] = @card if @card
    %i[test_tasks test_news test_site].each { |key| GatherPack::Digests.unregister(key) }
    Settings.instance.store = @original_store
    File.delete(@path) if File.exist?(@path)
  end

  test "lists each personal section with the site's choice selected" do
    get email_notices_url

    assert_response :success
    assert_select "h1", "Email notices"
    assert_select "p", text: /Choose how you hear about each feature\. The daily digest comes once a day around 7:00; the Weekly Infodump is the weekly announcements email\./
    assert_select "legend", text: "Tasks"
    assert_select "legend", text: "News"
    assert_select "legend", text: "Site only", count: 0
    assert_select "input[type=radio][name='email_notices[test_tasks]'][value=site][checked]"
    assert_select "label[for=email_notices_test_tasks_site]", "Use the site's choice (In the daily digest)"
    assert_select "label[for=email_notices_test_news_site]", "Use the site's choice (In the Weekly Infodump)"
    assert_select "label[for=email_notices_test_tasks_each]", "An email each time"
    assert_select "label[for=email_notices_test_tasks_daily]", "In the daily digest"
    assert_select "label[for=email_notices_test_tasks_weekly]", "In the Weekly Infodump"
    assert_select "label[for=email_notices_test_tasks_off]", "Off"
    assert_select "input[value=both]", count: 0
  end

  test "saves a choice and clears it with the site's choice" do
    patch email_notices_url, params: { email_notices: { test_tasks: "each", test_news: "site" } }

    assert_redirected_to email_notices_url
    assert_equal "each", NoticePreference.find_by(person: @alice, key: "test_tasks").delivery
    assert_nil NoticePreference.find_by(person: @alice, key: "test_news")
    assert_equal :each, GatherPack::Digests.delivery_for(:test_tasks, @alice)

    get email_notices_url
    assert_select "input[type=radio][name='email_notices[test_tasks]'][value=each][checked]"

    patch email_notices_url, params: { email_notices: { test_tasks: "off" } }
    assert_equal "off", NoticePreference.find_by(person: @alice, key: "test_tasks").delivery

    patch email_notices_url, params: { email_notices: { test_tasks: "site" } }
    assert_nil NoticePreference.find_by(person: @alice, key: "test_tasks")
    assert_equal :daily, GatherPack::Digests.delivery_for(:test_tasks, @alice)
  end

  test "refuses a choice that isn't offered and ignores sections that aren't" do
    patch email_notices_url, params: { email_notices: { test_tasks: "both" } }
    assert_redirected_to email_notices_url
    assert_equal "Choose one of the options", flash[:alert]
    assert_not NoticePreference.exists?(person: @alice)

    patch email_notices_url, params: { email_notices: { test_site: "off", test_other: "off" } }
    assert_not NoticePreference.exists?(person: @alice)
  end

  test "changes only the signed-in person's choices" do
    bob = people(:two)
    NoticePreference.create!(person: bob, key: "test_tasks", delivery: "weekly")

    patch email_notices_url, params: { email_notices: { test_tasks: "site" } }

    assert_equal "weekly", NoticePreference.find_by(person: bob, key: "test_tasks").delivery
  end

  test "there's no page while summaries are off" do
    Settings[:feature_digests] = "false"

    get email_notices_url
    assert_redirected_to root_url

    patch email_notices_url, params: { email_notices: { test_tasks: "each" } }
    assert_redirected_to root_url
    assert_not NoticePreference.exists?(person: @alice)
  end

  test "the person's own profile links to the page while there's a choice to make" do
    get person_url(@alice)
    assert_select "a[href=?]", email_notices_path, text: "Email notices"

    get person_url(people(:two))
    assert_select "a[href=?]", email_notices_path, count: 0

    Settings[:feature_digests] = "false"
    get person_url(@alice)
    assert_select "a[href=?]", email_notices_path, count: 0
  end

  test "the choices register as a Notifications page card where that seam exists" do
    sections = Module.new do
      class << self
        def registered
          @registered ||= {}
        end

        def register(key, **options)
          registered[key] = options
        end
      end
    end
    original = GatherPack.send(:remove_const, :NotificationSections) if GatherPack.const_defined?(:NotificationSections, false)
    GatherPack.const_set(:NotificationSections, sections)

    assert_not GatherPack::Digests.on_notifications_page?
    GatherPack::Digests.register_notification_section

    section = sections.registered.fetch(:email_notices)
    assert_equal "email_notices/form", section[:partial]
    assert section[:visible].call(nil)
    assert GatherPack::Digests.on_notifications_page?

    Settings[:feature_digests] = "false"
    assert_not section[:visible].call(nil)
  ensure
    GatherPack.send(:remove_const, :NotificationSections) if GatherPack.const_defined?(:NotificationSections, false) && GatherPack::NotificationSections == sections
    GatherPack.const_set(:NotificationSections, original) if original
  end

  test "where the Notifications page takes cards, the choices go there" do
    skip "needs the Notifications page" unless defined?(GatherPack::NotificationSections)

    GatherPack::Digests.register_notification_section

    get email_notices_url
    assert_redirected_to notifications_url

    patch email_notices_url, params: { email_notices: { test_tasks: "each" } }
    assert_redirected_to notifications_url(anchor: "email-notices")

    get person_url(@alice)
    assert_select "a[href=?]", email_notices_path, count: 0
  ensure
    GatherPack::NotificationSections.unregister(:email_notices) if defined?(GatherPack::NotificationSections)
  end
end
