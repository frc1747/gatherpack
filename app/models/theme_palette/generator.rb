module ThemePalette
  # Turns a theme's base colors into the skin's color tokens, for light, dark
  # and print. Plain Ruby: it reads the four color fields and custom_css off
  # whatever it's given, and touches neither the database nor the view.
  class Generator
    TEXT_RATIO = 4.5
    BORDER_RATIO = 3.0

    # The skin's own values (skin/_tokens.scss), used for anything not picked.
    DEFAULTS = {
      light: {
        brand: "#6d6753", page: "#ebe6d8", surface: "#fffdf6", raised: "#f3efe3", subtle: "#f6f3e9",
        border: "#ddd7c2", input_border: "#958e76", text: "#2b2716", text_soft: "#403a22", muted: "#635d49",
        success: "#146c43"
      },
      dark: {
        brand: "#7a745f", page: "#1c1a12", surface: "#27241a", raised: "#322e22", subtle: "#322e22",
        border: "#454032", input_border: "#7f7963", text: "#f3efe3", text_soft: "#ddd7c2", muted: "#b5ae97",
        success: "#4cc38a"
      }
    }.freeze

    DANGER = "#dc3545"

    # Starting hues for syntax colors, nudged until each reads on the editor.
    CODE_HUES = {
      keyword: "#cfa757", comment: "#96959d", operator: "#8a8678", string: "#83a655",
      atom: "#4f93b5", number: "#7fa32e", name: "#b08f3f", class: "#90a35b"
    }.freeze

    # Elements painted with --gp-surface. When the page and the cards are too
    # far apart for one text color to read on both, these get their own.
    SURFACES = [
      ".card", ".modal", ".modal-content", ".dropdown-menu", ".popover", ".offcanvas", ".offcanvas-md",
      ".offcanvas-lg", ".sidebar", "header.navbar", ".table", ".list-group", ".accordion", ".alert",
      ".breadcrumb-container", ".pagination", ".nav-tabs .nav-link.active", ".navtab", ".form-control",
      ".form-select", ".form-check-input", ".input-group-text", ".hw-combobox", ".hw-combobox__dialog",
      ".hw-combobox__listbox", ".fc", ".cm-editor", "trix-editor", "trix-toolbar"
    ].freeze

    # What the skin's :root derives from the context tokens. A custom property
    # resolves where it's declared, so a surface has to restate these.
    SURFACE_MAP = {
      "--bs-body-color" => "text", "--bs-body-color-rgb" => "text-rgb",
      "--bs-emphasis-color" => "text", "--bs-emphasis-color-rgb" => "text-rgb",
      "--bs-heading-color" => "text", "--bs-card-color" => "text", "--card-fg" => "text",
      "--pair-a-fg" => "text", "--pair-b-fg" => "text", "--pair-c-fg" => "text",
      "--hw-dialog-label-color" => "text", "--fc-button-text-color" => "text",
      "--bs-secondary-color" => "muted", "--bs-secondary-color-rgb" => "muted-rgb",
      "--bs-tertiary-color" => "muted", "--bs-tertiary-color-rgb" => "muted-rgb",
      "--bs-secondary-rgb" => "muted-rgb", "--hw-group-color" => "muted",
      "--bs-link-color" => "accent", "--bs-link-color-rgb" => "accent-rgb", "--hw-focus-color" => "accent",
      "--bs-link-hover-color" => "accent-hover", "--bs-link-hover-color-rgb" => "accent-hover-rgb",
      "--bs-primary-text-emphasis" => "accent-hover",
      "--bs-success" => "success", "--bs-success-rgb" => "success-rgb", "--bs-success-text-emphasis" => "success",
      "--bs-border-color" => "border", "--bs-border-color-translucent" => "border",
      "--fc-border-color" => "border", "--fc-button-border-color" => "border",
      "--fc-button-hover-border-color" => "border",
      "--bs-form-valid-border-color" => "input-border", "--hw-border-color" => "input-border",
      **CODE_HUES.keys.to_h { |name| [ "--app-code-#{name}", "code-#{name}" ] }
    }.freeze

    Palette = Struct.new(:tokens, :surface_tokens, :page, :surface, :raised, :subtle, :soft, keyword_init: true) do
      def split?
        surface_tokens.present?
      end
    end

    def initialize(theme)
      @picks = ThemePalette::FIELDS.index_with { |field| pick_from(theme, field) }
      @custom_css = theme.custom_css.to_s
    end

    def chosen?
      @picks.values.any?
    end

    # Empty with no picks, so the skin's own defaults stand.
    def css
      return "" unless chosen?

      light = palette(:light)
      [
        root_block(":root", light, scheme: light.surface.dark? ? "dark" : "light"),
        root_block(":root[data-bs-theme=dark]", palette(:dark), scheme: "dark"),
        surface_block(light),
        print_block
      ].compact.join("\n")
    end

    # Picked pairs that can't reach 4.5:1, and editor rules that can undo the palette.
    def warnings
      picked_text_warnings + white_on_brand_warnings + editor_rule_warnings
    end

    def picked_text_readable?
      text = @picks[:text_color]
      return true unless text

      light = palette(:light)
      [ light.page, light.surface ].all? { |background| text.contrast(background) >= TEXT_RATIO }
    end

    # What a color field resolves to in light mode, picked or not.
    def effective(field)
      palette(:light).then do |light|
        {
          brand_color: light.tokens["--gp-brand"],
          background_color: light.page.to_s,
          surface_color: light.surface.to_s,
          text_color: light.tokens["--gp-text"]
        }.fetch(field)
      end
    end

    def palette(mode)
      (@palettes ||= {})[mode] ||= build(mode, @picks)
    end

    private

    def pick_from(theme, field)
      value = theme.public_send(field)
      Color.parse(value) if Color.valid?(value)
    end

    def default(mode, name)
      Color.parse(DEFAULTS.fetch(mode).fetch(name))
    end

    def build(mode, picks)
      neutrals = neutrals_for(mode, picks)
      fill = brand_fill(mode, picks[:brand_color], neutrals)
      surface_group = neutrals.values_at(:surface, :raised, :subtle)
      surface_ink = ink_for(mode, picks, surface_group, neutrals)
      soft = tint(neutrals[:surface], fill, surface_ink)
      all = [ neutrals[:page], *surface_group, soft ]

      if ink_for(mode, picks, all, neutrals)
        tokens = context_tokens(mode, picks, all, neutrals, fill).merge(mode_tokens(fill, neutrals, soft, surface_ink))
        Palette.new(tokens:, **neutrals, soft:)
      else
        page_tokens = context_tokens(mode, picks, [ neutrals[:page] ], neutrals, fill)
        Palette.new(
          tokens: page_tokens.merge(mode_tokens(fill, neutrals, soft, surface_ink)),
          surface_tokens: context_tokens(mode, picks, [ *surface_group, soft ], neutrals, fill),
          **neutrals, soft:
        )
      end
    end

    # -- Neutrals -------------------------------------------------------------

    def neutrals_for(mode, picks)
      return default_neutrals(mode) unless picks[:background_color] || picks[:surface_color]

      mode == :light ? light_neutrals(picks) : dark_neutrals(picks)
    end

    def default_neutrals(mode)
      %i[page surface raised subtle].index_with { |name| default(mode, name) }
    end

    def light_neutrals(picks)
      page = picks[:background_color] || default(:light, :page)
      surface = picks[:surface_color] || worked_out_surface(page)
      { page:, surface: }.merge(steps_from(surface))
    end

    # Only the hue comes from the picks: a dark page tinted like the light one.
    def dark_neutrals(picks)
      base = picks[:background_color] || picks[:surface_color]
      tint = base.with_saturation([ base.saturation, 0.25 ].min)
      {
        page: tint.with_lightness(0.09), surface: tint.with_lightness(0.13),
        raised: tint.with_lightness(0.17), subtle: tint.with_lightness(0.17)
      }
    end

    def worked_out_surface(page)
      amount = page.dark? ? 0.06 : 0.6
      [ 1, 0.75, 0.5, 0.25, 0 ].map { |scale| page.mix(Color::WHITE, amount * scale) }
        .find { |candidate| shared_ink([ page, candidate ]) }
    end

    # One step away from the surface, in whichever direction still leaves a
    # text color that reads on all of them.
    def steps_from(surface)
      target, amount = surface.dark? ? [ Color::WHITE, 0.07 ] : [ Color::BLACK, 0.05 ]
      first = step_pair(surface, target, amount)
      return first if shared_ink([ surface, *first.values ])

      step_pair(surface, target == Color::WHITE ? Color::BLACK : Color::WHITE, amount)
    end

    def step_pair(surface, target, amount)
      { raised: surface.mix(target, amount), subtle: surface.mix(target, amount / 2) }
    end

    # -- Inks -----------------------------------------------------------------

    def shared_ink(backgrounds)
      [ Color::BLACK, Color::WHITE ].find { |ink| readable_on?(ink, backgrounds) }
    end

    def readable_on?(color, backgrounds, ratio = TEXT_RATIO)
      backgrounds.all? { |background| color.contrast(background) >= ratio }
    end

    # Automatic text for these backgrounds, or nil if no color reads on them all.
    def ink_for(mode, picks, backgrounds, neutrals)
      default_text = default(mode, :text)
      return default_text if !neutrals_picked?(picks) && readable_on?(default_text, backgrounds)

      tint = neutrals[:page]
      dark = tint.with_saturation([ tint.saturation, 0.3 ].min).with_lightness(0.12)
      light = tint.with_saturation([ tint.saturation, 0.3 ].min).with_lightness(0.95)
      candidates = backgrounds.map { |background| background.contrast(dark) }.min >=
        backgrounds.map { |background| background.contrast(light) }.min ? [ dark, light ] : [ light, dark ]
      [ *candidates, Color::BLACK, Color::WHITE ].find { |ink| readable_on?(ink, backgrounds) }
    end

    def neutrals_picked?(picks)
      picks[:background_color] || picks[:surface_color]
    end

    # The side a color moves toward to gain contrast on these backgrounds.
    def side_of(color, backgrounds)
      color.luminance < backgrounds.first.luminance ? Color::BLACK : Color::WHITE
    end

    # Lightness moved in small steps until the color reads, keeping its hue.
    def readable(color, backgrounds, ratio, toward)
      step = toward == Color::BLACK ? -0.01 : 0.01
      start = color.lightness
      101.times do |index|
        candidate = color.with_lightness((start + step * index).clamp(0.0, 1.0))
        return candidate if readable_on?(candidate, backgrounds, ratio)
      end
      toward
    end

    # -- Brand ----------------------------------------------------------------

    def brand_fill(mode, picked, neutrals)
      return picked if picked && mode == :light
      return default(mode, :brand) unless picked

      dark_fill(picked, neutrals)
    end

    # Dark enough for white text, which a site's own widgets assume on
    # --bs-primary, and light enough to stand out from the surface.
    def dark_fill(brand, neutrals)
      start = brand.lightness
      whitest = (0..100).lazy.map { |index| brand.with_lightness((start - index * 0.01).clamp(0.0, 1.0)) }
        .find { |candidate| candidate.best_ink == Color::WHITE }
      backgrounds = neutrals.values_at(:page, :surface)
      visible = (0..100).lazy.map { |index| whitest.with_lightness((whitest.lightness + index * 0.01).clamp(0.0, 1.0)) }
        .take_while { |candidate| candidate.best_ink == Color::WHITE }
        .find { |candidate| readable_on?(candidate, backgrounds, BORDER_RATIO) }
      visible || whitest
    end

    def tint(surface, fill, ink)
      [ 0.14, 0.1, 0.07, 0.04, 0 ].map { |amount| surface.mix(fill, amount) }
        .find { |candidate| readable_on?(ink, [ candidate ]) }
    end

    def hover_of(fill, on_fill)
      away = on_fill == Color::WHITE ? -0.08 : 0.08
      hover = fill.shift(away)
      hover == fill ? fill.shift(-away) : hover
    end

    # -- Tokens ---------------------------------------------------------------

    def with_rgb(name, color)
      { "--gp-#{name}" => color.to_s, "--gp-#{name}-rgb" => color.rgb }
    end

    def mode_tokens(fill, neutrals, soft, surface_ink)
      on_fill = fill.best_ink
      hover = hover_of(fill, on_fill)
      surface = neutrals[:surface]
      shadow = surface.dark? ? "0, 0, 0" : surface_ink.rgb
      {
        **with_rgb("brand", fill), **with_rgb("brand-hover", hover),
        "--gp-brand-soft" => soft.to_s, "--gp-on-brand" => on_fill.to_s,
        **with_rgb("page", neutrals[:page]), **with_rgb("surface", surface), **with_rgb("raised", neutrals[:raised]),
        "--gp-subtle" => neutrals[:subtle].to_s,
        "--gp-shadow" => "0 1px 2px rgba(#{shadow}, #{surface.dark? ? '.4' : '.06'})",
        "--gp-shadow-raised" => "0 8px 24px rgba(#{shadow}, #{surface.dark? ? '.5' : '.12'})",
        "--gp-logo-tile" => surface.dark? ? surface_ink.to_s : "transparent",
        "--gp-icon-invert" => surface.dark? ? "1" : "0"
      }
    end

    # The tokens that depend on what they're read against.
    def context_tokens(mode, picks, backgrounds, neutrals, fill)
      ink = ink_for(mode, picks, backgrounds, neutrals)
      side = side_of(ink, backgrounds)
      background = backgrounds.first
      text = (mode == :light && picks[:text_color]) || ink
      base = readable_on?(text, backgrounds) ? text : ink
      base_side = side_of(base, backgrounds)
      accent = readable(fill, backgrounds, TEXT_RATIO, side)
      success_base = default(mode, :success)
      success_soft = neutrals[:surface].mix(success_base, 0.14)
      on_surfaces = backgrounds.include?(neutrals[:surface]) ? [ *backgrounds, success_soft ] : backgrounds
      success = readable(success_base, on_surfaces, TEXT_RATIO, side)

      tokens = {
        **with_rgb("accent", accent),
        **with_rgb("accent-hover", accent.shift(side == Color::BLACK ? -0.08 : 0.08)),
        **with_rgb("success", success),
        "--gp-success-soft" => success_soft.to_s,
        "--gp-on-success" => success.best_ink.to_s,
        **with_rgb("text", text),
        "--gp-text-soft" => readable(base.mix(background, 0.15), backgrounds, TEXT_RATIO, base_side).to_s,
        **with_rgb("muted", readable(base.mix(background, 0.36), backgrounds, TEXT_RATIO, base_side)),
        "--gp-border" => background.mix(ink, 0.13).to_s,
        "--gp-input-border" => readable(background.mix(ink, 0.45), backgrounds, BORDER_RATIO, side).to_s
      }
      CODE_HUES.each do |name, hex|
        tokens["--gp-code-#{name}"] = readable(Color.parse(hex), backgrounds, TEXT_RATIO, side).to_s
      end
      danger = danger_for(backgrounds, side)
      danger ? tokens.merge("--bs-danger" => danger.to_s, "--bs-danger-rgb" => danger.rgb) : tokens
    end

    # Only when Bootstrap's own red wouldn't read here.
    def danger_for(backgrounds, side)
      red = Color.parse(DANGER)
      readable(red, backgrounds, TEXT_RATIO, side) unless readable_on?(red, backgrounds)
    end

    # -- CSS ------------------------------------------------------------------

    def declarations(tokens)
      tokens.map { |name, value| "  #{name}: #{value};" }.join("\n")
    end

    def root_block(selector, palette, scheme:)
      "#{selector} {\n  color-scheme: #{scheme};\n#{declarations(palette.tokens)}\n}"
    end

    # Light mode on screen only: dark mode's surfaces match its page, and paper
    # is always the light set.
    def surface_block(light)
      return unless light.split?

      mapped = SURFACE_MAP.map { |name, token| "  #{name}: var(--gp-#{token});" }
      <<~CSS.strip
        @media screen {
        #{SURFACES.map { |selector| ":root:not([data-bs-theme=dark]) #{selector}" }.join(",\n")} {
          color: var(--gp-text);
        #{declarations(light.surface_tokens)}
        #{mapped.join("\n")}
        }
        }
      CSS
    end

    # Browsers drop backgrounds on paper, so dark picks would leave light ink
    # on white. Those fall back to the skin's light values for printing.
    def print_block
      picks = print_picks
      light = build(:light, picks)
      "@media print {\n#{root_block(":root, :root[data-bs-theme=dark]", light, scheme: "light")}\n}"
    end

    def print_picks
      @picks.dup.tap do |picks|
        picks[:background_color] = nil if picks[:background_color]&.dark?
        picks[:surface_color] = nil if picks[:surface_color]&.dark?
        picks[:text_color] = nil if picks[:text_color] && picks[:text_color].contrast(Color::WHITE) < TEXT_RATIO
      end
    end

    # -- Warnings -------------------------------------------------------------

    def picked_text_warnings
      text = @picks[:text_color]
      return [] unless text

      light = palette(:light)
      { "Page background" => light.page, "Cards and menus" => light.surface }.filter_map do |label, background|
        ratio = text.contrast(background)
        "Text on #{label} is hard to read (#{ratio.floor(1)}:1, aim for 4.5:1)." if ratio < TEXT_RATIO
      end
    end

    def white_on_brand_warnings
      brand = @picks[:brand_color]
      return [] unless brand

      ratio = Color::WHITE.contrast(brand)
      return [] if ratio >= TEXT_RATIO

      [ "White text is hard to read on Brand (#{ratio.floor(1)}:1). The app uses black text there, " \
        "but anything your site builds with white text on the brand color won't be readable." ]
    end

    EDITOR_SELECTOR = /\.cm-[\w-]+|\btrix-[\w-]+|\.trix-[\w-]+/
    COLOR_PROPERTY = /(?:\A|[;\s])(?:color|background(?:-color)?)\s*:/i

    def editor_rule_warnings
      @custom_css.scan(/([^{}]+)\{([^{}]*)\}/).filter_map do |selector, body|
        selector = selector.squish
        next unless selector.match?(EDITOR_SELECTOR) && body.match?(COLOR_PROPERTY)

        "Custom CSS sets a color on the editors (#{selector}). It can make them hard to read."
      end.uniq
    end
  end
end
