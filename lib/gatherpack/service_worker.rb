require "digest"

module GatherPack
  # Names the version of the service worker's asset cache, so a new deploy
  # starts a new cache and the old one is deleted.
  module ServiceWorker
    class << self
      # A digest of the app's asset manifest. Without a precompiled manifest
      # (development, test) it uses each asset's path, size and mtime, which is
      # cheap and changes whenever an asset does.
      def version
        return compute_version if Rails.application.config.enable_reloading

        @version ||= compute_version
      end

      private

      def compute_version
        Digest::SHA256.hexdigest(manifest_content).first(12)
      end

      def manifest_content
        manifest = Rails.public_path.join("assets", ".manifest.json")
        return manifest.read if manifest.exist?

        Rails.application.assets.load_path.assets.map { |asset|
          stat = File.stat(asset.path)
          "#{asset.logical_path}:#{stat.size}:#{stat.mtime.to_i}"
        }.sort.join("\n")
      end
    end
  end
end
