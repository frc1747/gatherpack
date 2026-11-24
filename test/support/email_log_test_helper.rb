# Shared by the sent email log tests: a private settings store with the
# feature switched on, and a Resend gateway whose API calls are stubbed.
module EmailLogTestHelper
  extend ActiveSupport::Concern

  included do
    setup do
      @settings_path = Rails.root.join("tmp", "settings-email-log-#{Process.pid}-#{object_id}.pstore").to_s
      @original_settings_store = Settings.instance.store
      Settings.instance.store = PStore.new(@settings_path, true)
      Settings[:feature_email_log] = "true"
    end

    teardown do
      Settings.instance.store = @original_settings_store
      File.delete(@settings_path) if File.exist?(@settings_path)
    end
  end

  def turn_off_email_log
    Settings[:feature_email_log] = "false"
  end

  def resend_gateway(secret: nil)
    Gateway::ResendSendingGateway.create!(name: "Resend", api_token: "re_test", sender: "team@example.com", secret: secret)
  end

  def postmark_gateway
    Gateway::PostmarkSendingGateway.create!(name: "Postmark", api_token: "pm_test", sender: "team@example.com")
  end

  # Replaces a singleton method for the length of the block.
  def stubbing(object, method_name, implementation)
    original = object.method(method_name)
    object.define_singleton_method(method_name, &implementation)
    yield
  ensure
    object.singleton_class.send(:remove_method, method_name)
    object.define_singleton_method(method_name, original) if original.owner == object.singleton_class
  end
end
