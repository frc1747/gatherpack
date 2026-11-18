require "pstore"
require "tmpdir"

# Turns the flag on against a throwaway settings file, so a test never writes
# storage/settings.pstore, and puts every value back afterwards.
module MyGatherpackTestHelper
  def turn_on_my_gatherpack(title: "Northwind Community")
    @saved_store = Settings.instance.store
    @saved_flag = Settings.get(:feature_my_gatherpack).instance_variable_get(:@value)
    @saved_title = Settings.get(:title).instance_variable_get(:@value)
    @settings_dir = Dir.mktmpdir
    Settings.instance.store = PStore.new(File.join(@settings_dir, "settings.pstore"), true)
    Settings[:feature_my_gatherpack] = "true"
    Settings[:title] = title
  end

  def restore_my_gatherpack
    Settings.get(:feature_my_gatherpack).instance_variable_set(:@value, @saved_flag)
    Settings.get(:title).instance_variable_set(:@value, @saved_title)
    Settings.instance.store = @saved_store
    FileUtils.remove_entry(@settings_dir)
  end

  def create_login(first_name, admin: false)
    user = User.create!(email: "#{first_name.downcase}@example.com", password: "Password1!", admin: admin)
    Person.create!(user: user, first_name: first_name, last_name: "Tester")
    user
  end
end
