module GatherPack
  # What a person can do with a link or text shared to the installed app from
  # another app on their phone. A feature registers an action; the share page
  # offers every action visible to the signed-in user.
  module ShareActions
    Action = Struct.new(:key, :label, :visible, :path, keyword_init: true)
    Shared = Struct.new(:url, :text, :title, keyword_init: true)

    URL_PATTERN = %r{https?://[^\s<>"']+}i

    @actions = {}

    class << self
      # `visible` takes the signed-in user; `path` takes a Shared and returns
      # a path within this app (starting with a single "/"), never a full URL:
      # the share page redirects to it. Registering the same key again
      # replaces it, so reloading code is safe.
      def register(key, label:, path:, visible: nil)
        @actions[key] = Action.new(key: key, label: label, visible: visible, path: path)
      end

      def visible_for(user)
        @actions.values.select { |action| action.visible.nil? || action.visible.call(user) }
      end

      def path_for(action, shared)
        path = action.path.call(shared).to_s
        unless path.start_with?("/") && !path.start_with?("//")
          raise ArgumentError, "share action #{action.key} must return a path within the app, got #{path.inspect}"
        end
        path
      end

      # Phones differ on where they put the link: some send it as `url`, many
      # put it inside `text`, a few inside `title`.
      def shared_from(params)
        text = params[:text].to_s.strip
        title = params[:title].to_s.strip
        explicit = params[:url].to_s.strip
        url = explicit.match?(/\A#{URL_PATTERN}\z/o) ? explicit : [ explicit, text, title ].filter_map { |value| extract_url(value) }.first
        Shared.new(url: url, text: text.presence, title: title.presence)
      end

      def extract_url(value)
        match = value.to_s[URL_PATTERN] or return nil
        trim_trailing_punctuation(match)
      end

      # Drops sentence punctuation after a link, and a closing bracket only when
      # nothing in the link opened it, so "Bolt_(fastener)" stays whole.
      def trim_trailing_punctuation(url)
        loop do
          trimmed = url.sub(/[.,;:!?]+\z/, "")
          trimmed = trimmed.chop if trimmed.end_with?(")") && trimmed.count(")") > trimmed.count("(")
          trimmed = trimmed.chop if trimmed.end_with?("]") && trimmed.count("]") > trimmed.count("[")
          return trimmed if trimmed == url
          url = trimmed
        end
      end

      # Registrations as they are now, so a test can change them and put them back.
      def snapshot
        @actions.dup
      end

      def restore(snapshot)
        @actions = snapshot.dup
      end
    end
  end
end
