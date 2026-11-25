module MyGatherpack
  # Sorts the sidebar items a person would see today into groups. It changes
  # what is shown, never what is allowed: every destination checks its own
  # policy.
  #
  # The table in config/initializers/my_gatherpack.rb places items by path
  # helper, so no feature's registration changes. An item that isn't placed in
  # the top or family groups, and isn't listed under Manage for this person,
  # goes in More, so a new feature can't vanish.
  class Menu
    ManagerCheck = Struct.new(:key, :paths, :check, keyword_init: true)

    HOME = GatherPack::Feature::NavItem.new(label: "Home", path: :root_path, icon: "house")

    # Run in the view context by resolve_nav_path. A manager's Time Clock also
    # lists their teams' punches, so theirs is filtered to their own.
    MY_HOURS_PATH = -> {
      if manager?
        time_clock_punches_path(q: { person_id_eq: current_user.person.id })
      else
        time_clock_punches_path
      end
    }

    @table = {}
    @manager_checks = {}

    class << self
      # { path_helper => { group => position } }
      attr_accessor :table
      attr_reader :manager_checks

      # Lets someone who manages no team still get the Manage group. +paths+
      # are the Manage items the check opens up; the block gets the person.
      # Registering the same key again replaces it, so reloading code is safe.
      def register_manager_check(key, paths: [], &check)
        raise ArgumentError, "register_manager_check needs a block" unless check
        @manager_checks[key] = ManagerCheck.new(key: key, paths: paths, check: check)
      end
    end

    def initialize(user)
      @user = user
      @person = user.person
    end

    def top
      [ HOME ] + placed(:top).map { |item| item.path == :time_clock_punches_path ? my_hours(item) : item }
    end

    def family
      placed(:family)
    end

    def more
      shown = (placed(:top) + family + manage).map(&:path)
      visible_items.reject { |item| shown.include?(item.path) }
    end

    # Team managers get every Manage item; anyone else only what their passing
    # checks open up.
    def manage
      return [] unless manages_anything?

      opened = passing_checks.flat_map(&:paths)
      items = visible_items.select do |item|
        opened.include?(item.path) || (@person.manager? && position(item, :manage))
      end
      items.sort_by.with_index { |item, index| [ position(item, :manage) || Float::INFINITY, index ] }
    end

    def manages_anything?
      @person.manager? || passing_checks.any?
    end

    private

    def visible_items
      @visible_items ||= GatherPack::Features.nav_sections.flat_map(&:last).select { |item| item.visible?(@user) }
    end

    def placed(group)
      visible_items.select { |item| position(item, group) }.sort_by { |item| position(item, group) }
    end

    def position(item, group)
      self.class.table.dig(item.path, group)
    end

    def passing_checks
      @passing_checks ||= self.class.manager_checks.values.select { |registration| registration.check.call(@person) }
    end

    def my_hours(item)
      item.dup.tap do |hours|
        hours.label = "My Hours"
        hours.path = MY_HOURS_PATH
      end
    end
  end
end
