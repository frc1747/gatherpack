module GatherPack
  # Summaries: what a person should hear about from each feature, gathered
  # into one daily email per person, the Weekly Infodump, or both. A feature
  # registers a section and says how it goes out with delivery:, usually from
  # the notice setting on its own setup page; the feature_digests flag turns
  # it all on.
  #
  # A feature registers its section in its initializer's to_prepare block,
  # guarded so it still works where this seam isn't merged:
  #
  #   GatherPack::Digests.register(:my_feature,
  #     label: "My feature",
  #     delivery: -> { Settings[:my_feature_notice] == "weekly" ? :weekly : :daily },
  #     build: ->(person, since:) {
  #       things = MyThing.waiting_for(person).where(created_at: since..)
  #       next if things.none?
  #
  #       GatherPack::Digests::Section.new(
  #         body: "<ul>#{things.map { |t| "<li>#{ERB::Util.h(t.name)}</li>" }.join}</ul>",
  #         link: Rails.application.routes.url_helpers.my_things_url)
  #     }) if defined?(GatherPack::Digests)
  #
  # delivery returns :daily, :weekly (the Weekly Infodump), :both or :off;
  # anything else counts as :off. build returns nil when there's nothing for
  # the person, or a Section. The heading (the label when left out) and link
  # are escaped here; the body is HTML, so the feature escapes anything
  # people typed.
  #
  # Keep the feature's own daily email, and skip it only while the seam
  # handles the section:
  #
  #   return if defined?(GatherPack::Digests) && GatherPack::Digests.handles?(:my_feature)
  module Digests
    DELIVERIES = %i[daily weekly both off].freeze

    Entry = Data.define(:key, :label, :delivery_proc, :build) do
      def delivery
        value = delivery_proc.call.to_s.strip.downcase.to_sym
        DELIVERIES.include?(value) ? value : :off
      rescue StandardError => e
        Rails.error.report(e, handled: true, context: { digest: key })
        :off
      end

      def daily?
        %i[daily both].include?(delivery)
      end

      def weekly?
        %i[weekly both].include?(delivery)
      end
    end

    Section = Data.define(:heading, :body, :link, :link_label) do
      def initialize(body:, heading: nil, link: nil, link_label: nil)
        super
      end
    end

    @entries = {}

    class << self
      def register(key, label:, delivery:, build:)
        key = key.to_sym
        @entries[key] = Entry.new(key, label, delivery, build)
      end

      def unregister(key)
        @entries.delete(key.to_sym)
      end

      def entries
        @entries.values
      end

      def [](key)
        @entries[key.to_sym]
      end

      def enabled?
        GatherPack::Features.enabled?(:digests)
      end

      # True while summaries are on and the section is registered: the
      # feature leaves its section to this seam and doesn't send its own
      # daily email.
      def handles?(key)
        enabled? && @entries.key?(key.to_sym)
      end

      # The daily email's HTML for the person, or nil when no daily section
      # has anything for them.
      def daily_content(person, since:, on: Date.current)
        sections = render_sections(entries.select(&:daily?), person, since: since)
        return if sections.empty?

        "<h1>#{on.strftime("%B %d")} Update for #{ERB::Util.h(person.display_name)}</h1>#{sections}"
      end

      # Called from Infodump#generate after the announcements. Appends the
      # weekly sections that have something for the person and says whether
      # it added any.
      def append_weekly(content, person, since: 7.days.ago)
        return false unless enabled?

        sections = render_sections(entries.select(&:weekly?), person, since: since)
        return false if sections.empty?

        content << sections
        true
      end

      private

      def render_sections(entries, person, since:)
        entries.filter_map { |entry| render(entry, build(entry, person, since)) }.join
      end

      def build(entry, person, since)
        entry.build.call(person, since: since)
      rescue StandardError => e
        # One broken section shouldn't stop everyone's summary.
        Rails.error.report(e, handled: true, context: { digest: entry.key, person_id: person.id })
        nil
      end

      def render(entry, section)
        return if section.nil? || section.body.blank?

        html = +"<h2>#{ERB::Util.h(section.heading.presence || entry.label)}</h2>#{section.body}"
        if section.link.present?
          label = section.link_label.presence || "Open #{entry.label}"
          html << "<p><a href=\"#{ERB::Util.h(section.link)}\">#{ERB::Util.h(label)}</a></p>"
        end
        html
      end
    end
  end
end
