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

    # Turns the old CSS variables into picks. Anything it can't use as a color
    # stays in css_variables, and with nothing to change it writes nothing.
    def use_css_variables_as_colors!
      picks, kept = read_css_variables
      left_out = []
      text = picks.delete(:text_color)
      if text && importable_text?(text, picks)
        picks[:text_color] = text
      elsif text
        left_out << IMPORTED_VARIABLES.key(:text_color)
      end

      if picks.any? || left_out.any?
        update!(picks.merge(css_variables: kept.map { |declaration| "#{declaration};" }.join("\n").presence))
      end

      ImportResult.new(
        imported: picks.keys.map { |field| IMPORTED_VARIABLES.key(field) },
        kept: kept.map { |declaration| declaration.split(":", 2).first.strip },
        left_out:
      )
    end

    private

    def read_css_variables
      css_declarations.each_with_object([ {}, [] ]) do |declaration, (picks, kept)|
        name, value = declaration.split(":", 2).map(&:strip)
        field = IMPORTED_VARIABLES[name]
        color = expand_hex(value.to_s.sub(/\s*!important\z/i, "")) if field

        if color
          picks[field] = color
        else
          kept << declaration
        end
      end
    end

    # Semicolons inside parentheses are part of a value, as in a data: URL. The
    # field's placeholder shows lines with no semicolon, so a line starting a
    # new variable also ends the one before.
    def css_declarations
      css_variables.to_s.gsub(%r{/\*.*?\*/}m, "").split(/;(?![^()]*\))/)
        .flat_map { |part| part.split(/\n(?=\s*--)/) }
        .map(&:strip).compact_blank
    end

    # `#abc` is a common way to write a variable, and a valid one to import.
    def expand_hex(value)
      return value.downcase if Color.valid?(value)

      "##{value[1..].chars.map { |digit| digit * 2 }.join}".downcase if value.match?(/\A#[0-9a-f]{3}\z/i)
    end

    def importable_text?(text, picks)
      saved = ThemePalette::FIELDS.index_with { |field| self[field] }
      Generator.new(Picks.new(**saved, **picks, text_color: text)).picked_text_readable?
    end
  end
end
