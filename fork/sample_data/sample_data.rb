# Loads the Northwind sample data into a GatherPack build: base.rb, then one
# file per feature in fork/features.txt, in manifest order. Run it with
# `bin/rails hbr:sample_data`; see fork/sample_data/README.md.
#
# Fork-only tooling (fork/specs/sample-data-spec.md). Everything except
# SampleData.run, the Builder and the guard is plain Ruby, so
# test/fork/sample_data_test.rb runs without Rails or a database.
require "date"

module Hbr
  module SampleData
    MANIFEST_PATH = "fork/features.txt"
    DATA_DIR = "fork/sample_data"
    FEATURES_DIR = "#{DATA_DIR}/features"
    EMAIL_DOMAIN = "example.com"
    PASSWORD = "password123"
    # db/seeds.rb names its people "Test First Name 0" and so on.
    SEED_PERSON_PREFIX = "Test First Name"

    class Error < StandardError; end

    @layers = {}
    @people = []

    class << self
      attr_reader :layers

      # Registers the base layer, which always loads first.
      def base(&block)
        @layers["base"] = block
      end

      # Registers a feature's layer under its branch name, for example
      # "feature/forms".
      def feature(branch, &block)
        @layers[branch] = block
      end

      # Declares the people a layer creates ("First Last"), so the guard
      # can tell sample people from real ones before anything runs.
      def people(*names)
        @people.concat(names.flatten)
      end

      def known_people
        @people.uniq
      end

      def reset!
        @layers = {}
        @people = []
      end

      # Active branches in the manifest, in order, as bin/fork-rebuild reads
      # them.
      def manifest_branches(text)
        text.each_line.filter_map do |line|
          branch = line.sub(/#.*/, "").strip
          branch unless branch.empty?
        end
      end

      # fork/sample_data/features/<branch without "feature/">.rb
      def feature_path(root, branch)
        File.join(root, FEATURES_DIR, "#{branch.delete_prefix("feature/")}.rb")
      end

      # What a load would do: the base file, each manifest branch with its
      # file (nil when missing), and a warning per missing file.
      def plan(root)
        manifest = File.join(root, MANIFEST_PATH)
        raise Error, "#{MANIFEST_PATH} not found under #{root}" unless File.exist?(manifest)

        branches = manifest_branches(File.read(manifest))
        files = branches.to_h { |branch| [ branch, (path = feature_path(root, branch)) && File.exist?(path) ? path : nil ] }
        warnings = files.select { |_, path| path.nil? }.map { |branch, _| "#{branch} has no sample data in #{FEATURES_DIR}/" }
        { base: File.join(root, DATA_DIR, "base.rb"), branches: branches, files: files, warnings: warnings }
      end

      # Loads the layer files a plan names, registering their blocks.
      def load_layers(plan)
        reset!
        load plan[:base]
        plan[:files].each_value { |path| load path if path }
      end

      # The first few records that look like real data: users outside
      # @example.com, and people neither db/seeds.rb nor a layer creates.
      def real_data
        users = User.where.not("email LIKE ?", "%@#{EMAIL_DOMAIN}").limit(3).pluck(:email)
        known = known_people
        people = []
        Person.find_each do |person|
          name = "#{person.first_name} #{person.last_name}"
          next if known.include?(name) || person.first_name.to_s.start_with?(SEED_PERSON_PREFIX)

          people << name
          break if people.size == 3
        end
        users.map { |email| "user #{email}" } + people.map { |name| "person #{name}" }
      end

      # Loads every layer. Returns the warnings. Raises Error when the
      # database has real data (unless forced) or a layer's expectation
      # fails.
      #
      # No outer transaction: records commit as they're saved, as they do in
      # the app. Form questions note content changes in after_commit, so
      # inside one transaction those would fire after the responses exist
      # and revoke their signatures. Every step is find-or-create, so a
      # failed load is fixed by running it again.
      def run(root:, force: false, out: $stdout, now: Time.zone.now)
        plan = plan(root)
        load_layers(plan)

        found = real_data
        if found.any? && !force
          raise Error, "This database has real data (#{found.join(", ")}). Sample data only loads into an empty " \
            "database or one that already holds sample data. Set SAMPLE_DATA_FORCE=1 to load it anyway."
        end

        clock = Clock.new(now, local: ->(*parts) { Time.zone.local(*parts) })
        builder = Builder.new(clock)
        builder.run_layer("base", @layers.fetch("base"))
        plan[:branches].each do |branch|
          builder.run_layer(branch, @layers[branch]) if @layers[branch]
        end
        builder.lines.each { |line| out.puts line }
        plan[:warnings].each { |warning| out.puts "warning: #{warning}" }
        plan[:warnings]
      end
    end

    # Dates relative to one moment, so every load is current.
    class Clock
      attr_reader :now

      # `local` builds a time in the site's zone from year, month, day,
      # hour and minute. Tests pass Time.new; the loader passes
      # Time.zone.local.
      def initialize(now, local: ->(*parts) { Time.new(*parts) })
        @now = now
        @local = local
      end

      def today
        now.to_date
      end

      def date(days)
        today + days
      end

      def days_from_now(days, hour: 9, min: 0)
        at(date(days), hour, min)
      end

      def days_ago(days, hour: 9, min: 0)
        days_from_now(-days, hour: hour, min: min)
      end

      def hours_ago(hours)
        now - (hours * 3600)
      end

      # The next given weekday after today (a week out when today is that
      # day), at the given time.
      def next_weekday(wday, hour: 9, min: 0)
        target = Date::DAYNAMES.index(wday.to_s.capitalize) or raise ArgumentError, "unknown weekday #{wday}"
        ahead = (target - today.wday) % 7
        at(date(ahead.zero? ? 7 : ahead), hour, min)
      end

      # A season covering today: the first of last month to June 30 of the
      # coming June (this year's while today is in June or earlier).
      def season
        first = (today << 1) - ((today << 1).day - 1)
        [ first, Date.new(today.month > 6 ? today.year + 1 : today.year, 6, 30) ]
      end

      private

      def at(day, hour, min)
        @local.call(day.year, day.month, day.day, hour, min)
      end
    end

    # What a layer's block gets: the clock, find-or-create helpers that
    # reset each record's attributes on every run, the base records, and
    # report lines.
    class Builder
      attr_reader :clock, :lines

      def initialize(clock)
        @clock = clock
        @lines = []
        @teams = {}
        @logins = {}
        @layer_lines = []
      end

      def run_layer(name, block)
        @layer_lines = []
        block.call(self)
        @lines << "#{name}: #{@layer_lines.join("; ")}" if @layer_lines.any?
      end

      # A summary line for this layer's output.
      def report(text)
        @layer_lines << text
      end

      # What in the base layer exercises a feature that adds no data.
      def note(text)
        report(text)
      end

      # Fails the load when the block is false.
      def expect(description)
        raise Error, "Sample data check failed: #{description}" unless yield
      end

      # Finds a record by `keys`, sets `attrs` (on every run, so relative
      # dates move forward), and saves it.
      def upsert!(model, keys, attrs = {})
        record = model.find_or_initialize_by(keys)
        record.assign_attributes(attrs)
        record.save! if record.new_record? || record.changed?
        record
      end

      def person!(first, last, **attrs)
        upsert!(Person, { first_name: first, last_name: last }, { display_name: "#{first} #{last}" }.merge(attrs))
      end

      # A login at @example.com with the shared password, linked to the
      # person of that name.
      def login!(key, local_part, first, last, admin: false)
        user = User.find_or_initialize_by(email: "#{local_part}@#{EMAIL_DOMAIN}")
        user.password = PASSWORD if user.new_record?
        user.admin = admin
        user.save!
        person = person!(first, last)
        person.update!(user: user) unless person.user_id == user.id
        @logins[key] = person
      end

      def login(key)
        @logins.fetch(key)
      end

      # Other records a later layer needs, by name (for example :season).
      def remember(key, record)
        (@records ||= {})[key] = record
      end

      def recall(key)
        (@records || {}).fetch(key)
      end

      def team!(key, name, type, color, parent = nil)
        team = Team.find_or_create_by!(name: name) { |t| t.team_type = type; t.color = color }
        team.update!(parent: parent) unless team.parent_id == parent&.id
        @teams[key] = team
      end

      def team(key)
        @teams.fetch(key)
      end

      # Base people have unique first names.
      def person(first)
        Person.find_by!(first_name: first)
      end

      def member!(person, team, manager: false)
        membership = Membership.find_or_create_by!(person: person, team: team) { |m| m.manager = manager }
        membership.update!(manager: true) if manager && !membership.manager
        membership
      end

      # Settings stores every value as a string ("true" for booleans).
      def setting(key, value)
        raise Error, "Unknown setting #{key}" unless Settings.get(key)

        Settings[key] = value.to_s
      end

      def enable_feature(key)
        setting(:"feature_#{key}", "true")
      end
    end
  end
end
