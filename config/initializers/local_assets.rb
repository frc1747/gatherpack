require "gatherpack/immutable_assets"

# Assets are served from the app, and Rails sends no Cache-Control for them in
# production unless told to. Development and test keep their own settings.
if Rails.env.production?
  Rails.application.config.middleware.insert_before 0, GatherPack::ImmutableAssets
end
