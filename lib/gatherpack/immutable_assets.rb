module GatherPack
  # Marks successful responses under /assets/ as cacheable for a year. Propshaft
  # digests those file names, so a changed file always gets a new URL. Files in
  # public/ (error pages, robots.txt, icons) keep their names and are left alone,
  # including when a dot segment ("/assets/../robots.txt") reaches them.
  class ImmutableAssets
    CACHE_CONTROL = "public, max-age=#{1.year.to_i}, immutable".freeze
    DOT_SEGMENT = /\A(?:\.|%2e){1,2}\z/i
    DIGESTED = /-[0-9a-f]{8}\.[\w.]+\z/

    def initialize(app)
      @app = app
    end

    def call(env)
      status, headers, body = @app.call(env)
      headers["Cache-Control"] = CACHE_CONTROL if status == 200 && digested_asset?(env["PATH_INFO"])
      [ status, headers, body ]
    end

    private

    def digested_asset?(path)
      return false unless path.start_with?("/assets/")

      segments = path.split("/")
      segments.none? { |segment| segment.match?(DOT_SEGMENT) } && segments.last.match?(DIGESTED)
    end
  end
end
