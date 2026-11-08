require "pstore"

class Settings
  include Singleton

  attr_accessor :store
  attr_reader :settings

  class Setting
    attr_reader :name, :setting_type, :description, :group, :setting_key, :default_value

    def initialize(store, setting_key, setting_type, name, default_value, group, description)
      @setting_key = setting_key
      @setting_type = setting_type || :text
      @name = name
      @value = store.transaction { store.fetch(setting_key, default_value) }
      @default_value = default_value
      @group = group || "Site Settings"
      @description = description || ""

      store.transaction do
        store[@setting_key] ||= default_value
      end
    end

    def value=(val)
      val = encryptor.encrypt(val.to_s) if secret? && val.present?

      store = Settings.instance.store
      store.transaction do
        store[@setting_key] = val
      end
      @value = val
    end

    def value
      case setting_type
      when :boolean
        @value == "true"
      when :secret
        decrypted_value
      else
        @value
      end
    end

    # Secret settings are stored encrypted, with the Active Record encryption
    # keys, and the settings page never shows them.
    def secret?
      setting_type == :secret
    end

    def in_group?(group)
      group == @group
    end

    private
      # Settings are registered before the encryption keys are configured, so
      # secrets are only decrypted when read.
      def decrypted_value
        return @value if @value.blank?

        if encryptor.encrypted?(@value)
          decrypt(@value)
        else
          # Saved before secret settings were encrypted: encrypt it now.
          plain = @value
          self.value = plain
          plain
        end
      rescue ActiveRecord::Encryption::Errors::Decryption
        Rails.logger.error("The #{@setting_key} setting can't be decrypted (were the encryption keys or SECRET_KEY_BASE changed?). Set it again on the settings page.")
        nil
      end

      # The bare encryptor only tries the current keys. A secret saved with
      # previous keys (e.g. derived ones, before explicit keys were set) is
      # read with those and saved again with the current ones.
      def decrypt(value)
        encryptor.decrypt(value)
      rescue ActiveRecord::Encryption::Errors::Decryption => error
        ActiveRecord::Encryption.config.previous_schemes.each do |scheme|
          plain = encryptor.decrypt(value, key_provider: scheme.key_provider)
          self.value = plain
          return plain
        rescue ActiveRecord::Encryption::Errors::Decryption
          next
        end
        raise error
      end

      def encryptor
        ActiveRecord::Encryption.encryptor
      end
  end

  class << self
    def [](setting)
      get(setting)&.value
    end

    def get(setting)
      instance.settings[setting]
    end

    def set(setting, val)
      instance.settings[setting].value = val
    end

    def []=(*args)
      set(*args)
    end

    def settings(group)
      instance.settings.values.filter { |setting| setting.in_group? group }
    end

    def groups
      instance.settings.values.map(&:group).uniq
    end

    def register_feature(feature)
      instance.send(:add_feature_setting, feature)
    end
  end

  private

  def add_feature_setting(feature)
    add_setting(
      feature.setting_key,
      :boolean,
      feature.label,
      feature.default_enabled.to_s,
      "Features",
      feature.description || "Enable or disable the #{feature.label} feature"
    )
  end

  def add_setting(setting_key, *args)
    @settings[setting_key] = Setting.new(@store, setting_key, *args)
  end

  def initialize
    @store = PStore.new("storage/settings.pstore")

    @settings = {}
    add_setting(:title, :string, "Site Name", "GatherPack", nil, "The name of the site")
    add_setting(:time_zone, :time_zone, "Time Zone", "Etc/UTC", nil, "The default time zone")
    add_setting(:infodump_day, :string, "Infodump Day", "Monday", nil, "The day of the week for the infodump to go out")
    add_setting(:infodump_time, :string, "Infodump Time", "5:30", nil, "The time of day for the infodump to go out (24h format)")

    add_setting(:local_auth, :boolean, "Enable Local Users", "true", "Local Auth", "Enable local log in capabilities")
    add_setting(:local_signup, :boolean, "Enable Creating Local Accounts", "true", "Local Auth", "Enable people to sign themselves up with an email & password")

    add_setting(:oauth_signup, :boolean, "Enable Creating OAuth Accounts", "true", "OAuth", "Enable people to sign themselves up with third party services")

    add_setting(:discord_oauth_client_id, :string, "Discord OAuth Client ID", "", "OAuth - Discord", "Client ID for Sign In via Discord")
    add_setting(:discord_oauth_client_secret, :secret, "Discord OAuth Client Secret", "", "OAuth - Discord", "Client ID for Sign In via Discord")

    add_setting(:github_oauth_client_id, :string, "Github OAuth Client ID", "", "OAuth - Github", "Client ID for Sign In via Github")
    add_setting(:github_oauth_client_secret, :secret, "Github OAuth Client Secret", "", "OAuth - Github", "Client ID for Sign In via Github")

    add_setting(:google_oauth_client_id, :string, "Google OAuth Client ID", "", "OAuth - Google", "Client ID for Sign In via Google")
    add_setting(:google_oauth_client_secret, :secret, "Google OAuth Client Secret", "", "OAuth - Google", "Client ID for Sign In via Google")

    add_setting(:time_clock_max_hours, :integer, "Time Clock Max Shift Hours", "12", "Time Clock", "Shifts longer than this many hours are flagged for review")
    add_setting(:time_kiosk_allow_unassigned, :boolean, "Kiosk: Allow Unassigned Punches", "true", "Time Clock", "Offer \"Start Unassigned\" at the kiosk for time that isn't part of a period. Turn off to require a period: if only one period applies, scanning a card clocks the person in to it right away.")
    add_setting(:time_kiosk_return_seconds, :integer, "Kiosk: Return to Welcome After (seconds)", "0", "Time Clock", "After a scan, go back to the Welcome screen after this many seconds. 0 keeps the person's screen up until the next scan.")
    add_setting(:time_kiosk_users_team, :team_select, "Kiosk: Who Can Open the Kiosk", "", "Time Clock", "Only admins and direct members of this team can open the time kiosk. Leave blank to let anyone signed in open it.")
    add_setting(:time_clock_hand_punches_managers_only, :boolean, "Only admins and managers enter punches by hand", "false", "Time Clock", "Members clock in and out at the kiosk, and can't create, edit or delete punches on the Time Clock pages")

    add_setting(:shirt_sizes, :string, "Shirt Sizes", "Youth S, Youth M, Youth L, S, M, L, XL, XXL, 3XL, 4XL", "People", "Comma-separated list of valid shirt sizes")
    add_setting(:gender_options, :string, "Gender Options", "M, F, X", "People", "Comma-separated list of valid gender options")
    add_setting(:guardianship_age_limit, :integer, "Guardianship Age Limit", "", "People", "Guardianship from a 'minor' relationship type ends when the child reaches this age. Leave blank for no limit")
    add_setting(:forms_creator_badge, :string, "Form Creator Badge", "", "Forms", "Name of a badge only admins assign. Holders can create event forms for teams they belong to, and manage and see responses to the forms they created, nothing more. Leave blank for none")
    add_setting(:forms_creator_highest_team, :string, "Highest Team for Form Creators", "", "Forms", "Name of the highest team form creators can use. They can own forms for, and ask, teams they belong to at or below it. Leave blank to allow only the teams they're directly in and the teams below those")
    add_setting(:guardianship_ends_without_birthday, :boolean, "End Guardianship Without a Birthday", "false", "People", "When an age limit is set, also end 'minor' guardianship for people with no birthday on file. Only applies when an age limit is set")
  end
end
