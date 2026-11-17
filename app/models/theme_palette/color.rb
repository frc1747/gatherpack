module ThemePalette
  # An sRGB color and the WCAG math the generator needs.
  class Color
    HEX = /\A#[0-9a-f]{6}\z/i

    attr_reader :red, :green, :blue

    def self.parse(hex)
      new(*hex.delete_prefix("#").scan(/../).map { |pair| pair.to_i(16) })
    end

    def self.valid?(value)
      value.is_a?(String) && value.match?(HEX)
    end

    def initialize(red, green, blue)
      @red, @green, @blue = [ red, green, blue ].map { |channel| channel.round.clamp(0, 255) }
    end

    BLACK = new(0, 0, 0)
    WHITE = new(255, 255, 255)

    def to_s
      format("#%02x%02x%02x", red, green, blue)
    end

    def rgb
      "#{red}, #{green}, #{blue}"
    end

    def ==(other)
      other.is_a?(Color) && to_s == other.to_s
    end

    def luminance
      @luminance ||= begin
        r, g, b = [ red, green, blue ].map do |channel|
          value = channel / 255.0
          value <= 0.03928 ? value / 12.92 : ((value + 0.055) / 1.055)**2.4
        end
        0.2126 * r + 0.7152 * g + 0.0722 * b
      end
    end

    def contrast(other)
      high, low = [ luminance, other.luminance ].minmax.reverse
      (high + 0.05) / (low + 0.05)
    end

    # Black or white, whichever reads better on this color. Always at least 4.58:1.
    def best_ink
      contrast(BLACK) >= contrast(WHITE) ? BLACK : WHITE
    end

    def dark?
      best_ink == WHITE
    end

    def mix(other, amount)
      self.class.new(
        red + (other.red - red) * amount,
        green + (other.green - green) * amount,
        blue + (other.blue - blue) * amount
      )
    end

    def hue
      hsl[0]
    end

    def saturation
      hsl[1]
    end

    def lightness
      hsl[2]
    end

    def with_lightness(value)
      self.class.from_hsl(hue, saturation, value)
    end

    def with_saturation(value)
      self.class.from_hsl(hue, value, lightness)
    end

    # Moves lightness by `amount` (0..1), keeping the hue.
    def shift(amount)
      with_lightness((lightness + amount).clamp(0.0, 1.0))
    end

    def self.from_hsl(hue, saturation, lightness)
      chroma = (1 - (2 * lightness - 1).abs) * saturation
      second = chroma * (1 - ((hue / 60.0) % 2 - 1).abs)
      base = lightness - chroma / 2
      r, g, b = [
        [ chroma, second, 0 ], [ second, chroma, 0 ], [ 0, chroma, second ],
        [ 0, second, chroma ], [ second, 0, chroma ], [ chroma, 0, second ]
      ][(hue / 60.0).floor % 6]
      new((r + base) * 255, (g + base) * 255, (b + base) * 255)
    end

    private

    def hsl
      @hsl ||= begin
        r, g, b = [ red, green, blue ].map { |channel| channel / 255.0 }
        min, max = [ r, g, b ].minmax
        delta = max - min
        lightness = (max + min) / 2
        if delta.zero?
          [ 0.0, 0.0, lightness ]
        else
          saturation = delta / (1 - (2 * lightness - 1).abs)
          hue = case max
          when r then ((g - b) / delta) % 6
          when g then (b - r) / delta + 2
          else (r - g) / delta + 4
          end
          [ hue * 60, saturation, lightness ]
        end
      end
    end
  end
end
