module GatherPack
  # Marks successful responses under /assets/ as cacheable for a year. Propshaft
  # digests those file names, so a changed file always gets a new URL. Files in
  # public/ (error pages, robots.txt, icons) keep their names and are left alone.
  class ImmutableAssets
    CACHE_CONTROL = "public, max-age=#{1.year.to_i}, immutable".freeze

    def initialize(app)
      @app = app
    end

    def call(env)
      status, headers, body = @app.call(env)
      if status == 200 && env["PATH_INFO"].start_with?("/assets/")
        headers["Cache-Control"] = CACHE_CONTROL
      end
      [ status, headers, body ]
    end
  end
end
