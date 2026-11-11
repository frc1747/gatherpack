class Theme < ApplicationRecord
  has_neat_id :thm
  has_paper_trail versions: { class_name: "AuditLog" }

  has_one_attached :logo
  has_one_attached :pwa_icon
  validates :logo, :pwa_icon, attachment: { content_types: AttachmentValidator::IMAGE_TYPES, max_size: 5.megabytes }

  validates :pwa_theme_color, format: { with: /\A#[0-9a-fA-F]{6}\z/, allow_blank: true, message: "must be a valid hex color (e.g. #ffffff)" }
  validates :pwa_background_color, format: { with: /\A#[0-9a-fA-F]{6}\z/, allow_blank: true, message: "must be a valid hex color (e.g. #ffffff)" }

  def self.instance
    first_or_create!
  end

  def pwa_icon_192
    pwa_icon.variant(resize_to_fill: [ 192, 192 ], format: :png) if pwa_icon_variable?
  end

  def pwa_icon_512
    pwa_icon.variant(resize_to_fill: [ 512, 512 ], format: :png) if pwa_icon_variable?
  end

  def apple_touch_icon
    pwa_icon.variant(resize_to_fill: [ 180, 180 ], format: :png) if pwa_icon_variable?
  end

  def favicon_32
    pwa_icon.variant(resize_to_fill: [ 32, 32 ], format: :png) if pwa_icon_variable?
  end

  # An icon that isn't an image Active Storage can resize (one stored before
  # uploads were checked) is left out, so the default icons show instead of
  # every page breaking.
  def pwa_icon_variable?
    pwa_icon.attached? && pwa_icon.variable?
  end

  def identifier_name
    "Theme"
  end

  def identifier_icon
    "palette"
  end
end
