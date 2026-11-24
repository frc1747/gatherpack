# A member-first set of screens, on while the feature_my_gatherpack flag is.
module MyGatherpack
  # A part of the home page. With +items+, its partial renders once per item, as
  # a row merged by date with the other sections in that column. Without, the
  # partial renders once, and rendering nothing leaves the section out.
  Section = Struct.new(:key, :partial, :column, :position, :enabled, :items, keyword_init: true) do
    def enabled?
      enabled.nil? || enabled.call
    end
  end

  DUE_SOON_DAYS = 3

  # One row in a home page list. +at+ orders the list; +ward+ is the first name
  # of the person it's for, when that isn't the viewer.
  Item = Struct.new(:title, :detail, :at, :path, :action, :icon, :ward, keyword_init: true) do
    def past_due?
      at.present? && at.past?
    end

    def due_soon?
      at.present? && at.to_date <= DUE_SOON_DAYS.days.from_now.to_date
    end
  end

  # A link to one of a person's own settings, beside Sign Out in the sidebar.
  AccountLink = Struct.new(:key, :label, :path, :visible, keyword_init: true)

  @sections = {}
  @account_links = {}

  class << self
    attr_reader :sections

    def enabled?
      GatherPack::Features.enabled?(:my_gatherpack)
    end

    # Features add to the home page from their own initializer, so this core
    # needs no code of theirs. +enabled+ is called with no arguments on each
    # request; +items+ runs in the view context and returns things with an +at+.
    # A :todo section must have +items+, because the heading counts them.
    # Registering the same key again replaces it, so reloading code is safe.
    def register_section(key, partial:, column:, position: 100, enabled: nil, items: nil)
      raise ArgumentError, "a :todo section needs items, so the heading can count them" if column == :todo && items.nil?

      @sections[key] = Section.new(key: key, partial: partial, column: column, position: position, enabled: enabled, items: items)
    end

    # The enabled sections in a column, in position order, then registration order.
    def sections_for(column)
      @sections.values
        .select { |section| section.column == column && section.enabled? }
        .each_with_index
        .sort_by { |section, index| [ section.position, index ] }
        .map(&:first)
    end

    # +path+ names a route helper. +visible+ runs in the view context.
    # Registering the same key again replaces it, so reloading code is safe.
    def register_account_link(key, label:, path:, visible: nil)
      @account_links[key] = AccountLink.new(key: key, label: label, path: path, visible: visible)
    end

    def account_links_for(view)
      @account_links.values.select { |link| link.visible.nil? || view.instance_exec(&link.visible) }
    end
  end
end
