require "test_helper"

class SettingsTest < ActiveSupport::TestCase
  MARKER = "GOCSPX-settings-plaintext-marker".freeze

  setup do
    @store_path = Rails.root.join("tmp", "settings-test-#{Process.pid}-#{SecureRandom.hex(4)}.pstore").to_s
    @original_store = Settings.instance.store
    @original_value = Settings.get(:google_oauth_client_secret).instance_variable_get(:@value)
    Settings.instance.store = PStore.new(@store_path)
  end

  teardown do
    Settings.get(:google_oauth_client_secret).instance_variable_set(:@value, @original_value)
    Settings.instance.store = @original_store
    FileUtils.rm_f(@store_path)
  end

  test "an OAuth client secret is not stored in clear in the settings file" do
    Settings[:google_oauth_client_secret] = MARKER

    assert_not File.binread(@store_path).include?(MARKER),
      "The Google OAuth client secret is readable in clear in #{File.basename(@store_path)}"
    assert_equal MARKER, Settings[:google_oauth_client_secret]
  end

  test "the OAuth client secrets are secret settings" do
    %i[discord_oauth_client_secret github_oauth_client_secret google_oauth_client_secret].each do |key|
      assert_equal :secret, Settings.get(key).setting_type, "#{key} isn't a secret setting"
    end
  end

  test "a secret saved before secrets were encrypted is read as is and encrypted on first read" do
    store = Settings.instance.store
    store.transaction { store[:google_oauth_client_secret] = MARKER }

    setting = Settings::Setting.new(store, :google_oauth_client_secret, :secret, "Google OAuth Client Secret", "", "OAuth - Google", nil)

    assert_equal MARKER, setting.value
    assert_not File.binread(@store_path).include?(MARKER), "the plain-text secret was not encrypted when it was read"
    assert_equal MARKER, Settings::Setting.new(store, :google_oauth_client_secret, :secret, "Google OAuth Client Secret", "", "OAuth - Google", nil).value
  end

  test "a secret saved with previous encryption keys is read and saved again with the current ones" do
    store = Settings.instance.store
    previous_keys = ActiveRecord::Encryption::DerivedSecretKeyProvider.new("a previous key")
    ActiveRecord::Encryption.config.previous_schemes << ActiveRecord::Encryption::Scheme.new(key_provider: previous_keys)
    store.transaction { store[:google_oauth_client_secret] = ActiveRecord::Encryption.encryptor.encrypt(MARKER, key_provider: previous_keys) }

    begin
      setting = Settings::Setting.new(store, :google_oauth_client_secret, :secret, "Google OAuth Client Secret", "", "OAuth - Google", nil)
      assert_equal MARKER, setting.value
    ensure
      ActiveRecord::Encryption.config.previous_schemes.pop
    end

    assert_equal MARKER, ActiveRecord::Encryption.encryptor.decrypt(store.transaction { store[:google_oauth_client_secret] })
  end

  test "a secret that can't be decrypted reads as blank" do
    store = Settings.instance.store
    store.transaction { store[:google_oauth_client_secret] = ActiveRecord::Encryption::Encryptor.new.encrypt(MARKER, key_provider: ActiveRecord::Encryption::DerivedSecretKeyProvider.new("some other key")) }

    setting = Settings::Setting.new(store, :google_oauth_client_secret, :secret, "Google OAuth Client Secret", "", "OAuth - Google", nil)

    assert_predicate setting.value, :blank?
  end
end
