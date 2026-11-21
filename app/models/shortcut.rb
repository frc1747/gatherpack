class Shortcut < ApplicationRecord
  belongs_to :team

  validates :color, format: { with: /\A#\h{6}\z/, message: "must be a valid hex color (e.g. #ffffff)" }
  validate :target_must_be_a_web_link

  # Shortcuts are links on other people's dashboards, so only http(s) URLs
  # and paths on this site are allowed.
  def self.safe_target?(target)
    target = target.to_s
    # Browsers drop tabs and newlines inside URLs, so "/\t/host" means "//host".
    return false if target.match?(/[[:space:][:cntrl:]]/)
    return !target.start_with?("//", "/\\") if target.start_with?("/")

    uri = URI.parse(target)
    %w[http https].include?(uri.scheme&.downcase) && uri.host.present?
  rescue URI::InvalidURIError
    false
  end

  def safe_target?
    self.class.safe_target?(target)
  end

  private
    def target_must_be_a_web_link
      errors.add(:target, "must be an http(s) URL or a path starting with /") unless safe_target?
    end
end
