module ThemePalette
  # The base colors on Theme: `#rrggbb` or nil, so these fields can't carry CSS.
  # Included from config/initializers/theme_palette.rb.
  module Choices
    extend ActiveSupport::Concern

    # What "Use these as my starting colors" reads out of the old variables.
    IMPORTED_VARIABLES = {
      "--bs-primary" => :brand_color,
      "--bs-body-bg" => :background_color,
      "--bs-card-bg" => :surface_color,
      "--bs-body-color" => :text_color
    }.freeze

    included do
      normalizes(*ThemePalette::FIELDS, with: ->(value) { value.strip.downcase.presence })

      validates(*ThemePalette::FIELDS, format: {
        with: Color::HEX,
        allow_nil: true,
        message: "must be a hex color like #336699"
      })
    end

    def palette_chosen?
      ThemePalette::FIELDS.any? { |field| self[field].present? }
    end

    # Turns the old CSS variables into picks, then clears them.
    def use_css_variables_as_colors!
      picks = imported_colors
      text = picks.delete(:text_color)
      picks[:text_color] = text if text && importable_text?(text, picks)
      update!(picks.merge(css_variables: nil))
    end

    private

    def imported_colors
      css_variables.to_s.each_line.each_with_object({}) do |line, picks|
        name, value = line.strip.delete_suffix(";").split(":", 2).map(&:strip)
        field = IMPORTED_VARIABLES[name]
        color = expand_hex(value.to_s.sub(/\s*!important\z/i, ""))
        picks[field] = color if field && color
      end
    end

    # `#abc` is a common way to write a variable, and a valid one to import.
    def expand_hex(value)
      return value.downcase if Color.valid?(value)

      "##{value[1..].chars.map { |digit| digit * 2 }.join}".downcase if value.match?(/\A#[0-9a-f]{3}\z/i)
    end

    def importable_text?(text, picks)
      candidate = Generator.new(Picks.new(**picks.slice(*ThemePalette::FIELDS), text_color: text))
      candidate.picked_text_readable?
    end
  end
end
