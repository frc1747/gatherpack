# Refuses to run unless connected to a local, marked demo database. Every
# script in fork/demo_db loads this first.
module DemoDb
  MARKER = "gatherpack-demo"
  LOCAL_HOSTS = [ "", "localhost", "127.0.0.1", "::1" ].freeze

  def self.guard!
    refuse("RAILS_ENV is production") if Rails.env.production?

    { ActiveRecord::Base => /\A[a-z0-9_]+_demo\z/, AbstractVersion => /\A[a-z0-9_]+_demo_versions\z/ }.each do |klass, pattern|
      connection = klass.connection
      name = connection.current_database
      host = klass.connection_db_config.host.to_s
      refuse("#{name} isn't a *_demo database") unless name.match?(pattern) && !name.include?("production")
      refuse("database host #{host.inspect} isn't local") unless LOCAL_HOSTS.include?(host)
      refuse("the server also holds gatherpack_production") if connection.select_value("select 1 from pg_database where datname = 'gatherpack_production'")
    end

    comment = ActiveRecord::Base.connection.select_value("select shobj_description(oid, 'pg_database') from pg_database where datname = current_database()")
    refuse("#{ActiveRecord::Base.connection.current_database} isn't marked #{MARKER}") unless comment.to_s.start_with?(MARKER)
  end

  def self.refuse(reason)
    abort "fork/demo_db: refusing to run: #{reason}"
  end
end
