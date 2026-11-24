module MyGatherpack
  # Sorts the sidebar items a person would see today into groups. It changes
  # what is shown, never what is allowed: every destination checks its own
  # policy.
  #
  # The table in config/initializers/my_gatherpack.rb places items by path
  # helper, so no feature's registration changes. An item that isn't placed in
  # the top or family groups, and isn't listed under Manage for this person,
  # goes under its own section heading, so a new feature can't vanish.
  class Menu
    ManagerCheck = Struct.new(:key, :paths, :check, keyword_init: true)

    HOME = GatherPack::Feature::NavItem.new(label: "Home", path: :root_path, icon: "house")

    # Manage's headed parts, in order. The table puts items in them.
    PARTS = { people: "People", time: "Time", money: "Money", content: "Content" }.freeze

    MY_HOURS_KEY = "my_hours"

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
      # { path_helper => { group => position, part: manage_part } }
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

    # Pages ticked "Show in the menu" that this person may open, by title.
    def reports
      @reports ||= begin
        pages = report_pages.to_a.select { |page| PagePolicy.new(@user, page).show? }.sort_by { |page| page.title.to_s.downcase }
        pages.map do |page|
          GatherPack::Feature::NavItem.new(label: page.title, path: Rails.application.routes.url_helpers.page_path(page), icon: page.identifier_icon).tap do |item|
            report_keys[item.path] = MenuPin.page_key(page)
          end
        end
      end
    end

    # The Pages list, for the end of Reports, when this person has it.
    def all_pages
      visible_items.find { |item| item.path == :pages_path }
    end

    # [[section_name, items]] for what the other groups don't show, in section
    # order. A section with nothing left is dropped.
    def sections
      shown = (placed(:top) + family + manage).map(&:path)
      GatherPack::Features.nav_sections.filter_map do |name, items|
        left = items.select { |item| item.visible?(@user) && !shown.include?(item.path) }
        [ name, left ] if left.any?
      end
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

    # [[part_key, heading, items]] in PARTS order. Manage items the table puts
    # in no part come first, under no heading. A part with nothing in it is
    # dropped.
    def manage_parts
      groups = manage.group_by { |item| part(item) }
      ([ nil ] + PARTS.keys).filter_map do |key|
        [ key, PARTS[key], groups[key] ] if groups[key]
      end
    end

    def manages_anything?
      @person.manager? || passing_checks.any?
    end

    # The person's pinned items, in the order pinned. A pin whose item isn't
    # in this person's menu now (its feature is off, or they can't see it) is
    # left out but kept.
    def pinned
      @pinned ||= begin
        items = pinnable.index_by { |item| pin_key(item) }
        pins.filter_map { |pin| items[pin.path_key] }
      end
    end

    # What a pin of this item is saved as, or nil when it can't be pinned.
    def pin_key(item)
      return MY_HOURS_KEY if item.path.equal?(MY_HOURS_PATH)
      return item.path.to_s if item.path.is_a?(Symbol)

      report_keys[item.path]
    end

    def pinned?(item)
      key = pin_key(item)
      key.present? && pin_keys.include?(key)
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

    def part(item)
      key = self.class.table.dig(item.path, :part)
      key if PARTS.key?(key)
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

    def report_pages
      return Page.none unless GatherPack::Features.enabled?(:pages)

      Pundit.policy_scope!(@user, Page).where(show_in_menu: true)
    end

    def report_keys
      @report_keys ||= {}
    end

    def pinnable
      reports # fills report_keys
      top + reports + family + sections.flat_map(&:last) + manage
    end

    def pins
      @pins ||= MenuPin.where(user_id: @user.id).order(:position, :created_at).to_a
    end

    def pin_keys
      @pin_keys ||= pins.map(&:path_key)
    end
  end
end
