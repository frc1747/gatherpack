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
      # the path (or URL) to send the person to. Registering the same key
      # again replaces it, so reloading code is safe.
      def register(key, label:, path:, visible: nil)
        @actions[key] = Action.new(key: key, label: label, visible: visible, path: path)
      end

      def visible_for(user)
        @actions.values.select { |action| action.visible.nil? || action.visible.call(user) }
      end

      def path_for(action, shared)
        action.path.call(shared)
      end

      # Phones differ on where they put the link: some send it as `url`, many
      # put it inside `text`, a few inside `title`.
      def shared_from(params)
        text = params[:text].to_s.strip
        title = params[:title].to_s.strip
        url = [ params[:url], text, title ].filter_map { |value| extract_url(value) }.first
        Shared.new(url: url, text: text.presence, title: title.presence)
      end

      def extract_url(value)
        match = value.to_s[URL_PATTERN] or return nil
        match.sub(/[.,;:!?)\]]+\z/, "")
      end

      def reset!
        @actions = {}
      end
    end
  end
end
