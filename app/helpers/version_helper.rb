module VersionHelper
  # The release this instance runs, from GATHERPACK_VERSION (set at image build
  # time from the git tag or branch). Falls back to `git describe` in
  # development, and is nil otherwise, in which case nothing is shown.
  def gatherpack_version
    version = ENV["GATHERPACK_VERSION"].presence || VersionHelper.development_version
    version&.sub(/\Av(?=\d)/, "")
  end

  # The commit this instance was built from, shortened, from GATHERPACK_REVISION.
  def gatherpack_revision
    ENV["GATHERPACK_REVISION"].presence&.first(7)
  end

  def self.development_version
    return unless Rails.env.development?
    @development_version ||= `git describe --tags --always 2>/dev/null`.strip.presence
  end
end
