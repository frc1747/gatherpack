require "test_helper"

class ThemePaletteGeneratorTest < ActiveSupport::TestCase
  Picks = ThemePalette::Picks
  Color = ThemePalette::Color
  TEXT_TOKENS = %w[--gp-text-soft --gp-muted --gp-accent --gp-accent-hover --gp-success].freeze
  CODE_TOKENS = ThemePalette::Generator::CODE_HUES.keys.map { |name| "--gp-code-#{name}" }.freeze

  MATRIX = {
    "production" => { brand_color: "#34b233", background_color: "#505050", surface_color: "#c8c8c8" },
    "very light" => { brand_color: "#ffff00", background_color: "#fefefe", surface_color: "#ffffff" },
    "very dark" => { brand_color: "#000000", background_color: "#000000", surface_color: "#111111" },
    "dark page, white cards" => { brand_color: "#ff0000", background_color: "#101010", surface_color: "#ffffff" },
    "saturated red" => { brand_color: "#ff0000", background_color: "#ff0000", surface_color: "#00ff00" },
    "saturated blue" => { brand_color: "#0000ff", background_color: "#0000ff", surface_color: "#ffff00" },
    "near grey" => { brand_color: "#7f7f80", background_color: "#777777", surface_color: "#808081" },
    "mid tones" => { brand_color: "#767676", background_color: "#747474", surface_color: "#787878" },
    "brand only" => { brand_color: "#34b233" },
    "pale brand only" => { brand_color: "#f8f8f8" },
    "navy brand only" => { brand_color: "#0a2240" },
    "page only, light" => { background_color: "#fff8e1" },
    "page only, dark" => { background_color: "#202020" },
    "page only, mid" => { background_color: "#777777" },
    "cards only, dark" => { surface_color: "#1a1a2e" },
    "picked text, light" => { background_color: "#ffffff", surface_color: "#f0f0f0", text_color: "#111111" }
  }.freeze

  def generator(**picks)
    ThemePalette::Generator.new(Picks.new(**picks))
  end

  def contexts(palette)
    if palette.split?
      [ [ palette.tokens, [ palette.page ] ],
        [ palette.surface_tokens, [ palette.surface, palette.raised, palette.subtle, palette.soft ] ] ]
    else
      [ [ palette.tokens, [ palette.page, palette.surface, palette.raised, palette.subtle, palette.soft ] ] ]
    end
  end

  def assert_reads(token, tokens, backgrounds, ratio, label)
    color = Color.parse(tokens.fetch(token))
    backgrounds.each do |background|
      contrast = color.contrast(background)
      assert_operator contrast.round(3), :>=, ratio,
        "#{label}: #{token} #{color} on #{background} is #{contrast.round(2)}:1"
    end
  end

  MATRIX.each do |name, picks|
    %i[light dark].each do |mode|
      test "#{name} in #{mode}: every derived pair is readable" do
        palette = generator(**picks).palette(mode)

        contexts(palette).each do |tokens, backgrounds|
          TEXT_TOKENS.each { |token| assert_reads(token, tokens, backgrounds, 4.5, name) }
          CODE_TOKENS.each { |token| assert_reads(token, tokens, backgrounds, 4.5, name) }
          assert_reads("--gp-input-border", tokens, backgrounds, 3.0, name)
          assert_reads("--gp-text", tokens, backgrounds, 4.5, name) unless picks[:text_color] && mode == :light
          assert_reads("--bs-danger", tokens, backgrounds, 4.5, name) if tokens.key?("--bs-danger")

          on_success = Color.parse(tokens.fetch("--gp-on-success"))
          assert_operator on_success.contrast(Color.parse(tokens.fetch("--gp-success"))), :>=, 4.5, name
        end

        on_brand = Color.parse(palette.tokens.fetch("--gp-on-brand"))
        assert_operator on_brand.contrast(Color.parse(palette.tokens.fetch("--gp-brand"))), :>=, 4.5, name
        assert_operator on_brand.contrast(Color.parse(palette.tokens.fetch("--gp-brand-hover"))), :>=, 4.5, name
      end
    end

    if picks[:brand_color]
      test "#{name}: dark mode keeps white text readable on the brand fill" do
        palette = generator(**picks).palette(:dark)
        brand = Color.parse(palette.tokens.fetch("--gp-brand"))

        assert_equal "#ffffff", palette.tokens.fetch("--gp-on-brand"), name
        assert_operator Color::WHITE.contrast(brand), :>=, 4.5, name
        assert_operator brand.contrast(palette.surface), :>=, 3.0, "#{name}: #{brand} vanishes on #{palette.surface}"
      end
    end

    test "#{name}: a picked pair appears in warnings exactly when it fails" do
      gen = generator(**picks)
      light = gen.palette(:light)
      text = picks[:text_color] && Color.parse(picks[:text_color])
      brand = picks[:brand_color] && Color.parse(picks[:brand_color])

      expected = {
        "Page background" => text && text.contrast(light.page) < 4.5,
        "Cards and menus" => text && text.contrast(light.surface) < 4.5,
        "on Brand" => brand && Color::WHITE.contrast(brand) < 4.5
      }
      expected.each do |label, fails|
        assert_equal !!fails, gen.warnings.any? { |warning| warning.include?(label) }, "#{name}: #{label}"
      end
    end
  end

  test "picked colors are used exactly in light mode" do
    picks = { brand_color: "#34b233", background_color: "#505050", surface_color: "#c8c8c8", text_color: "#111111" }
    tokens = generator(**picks).palette(:light).tokens

    assert_equal "#34b233", tokens["--gp-brand"]
    assert_equal "#505050", tokens["--gp-page"]
    assert_equal "#c8c8c8", tokens["--gp-surface"]
    assert_equal "#111111", tokens["--gp-text"]
  end

  test "a page and cards too far apart get their own text and accent" do
    palette = generator(brand_color: "#34b233", background_color: "#505050", surface_color: "#c8c8c8").palette(:light)

    assert palette.split?
    assert_not_equal palette.tokens["--gp-text"], palette.surface_tokens["--gp-text"]
    assert_not_equal palette.tokens["--gp-accent"], palette.surface_tokens["--gp-accent"]
  end

  test "with no picks it generates nothing" do
    gen = generator
    assert_equal "", gen.css
    assert_empty gen.warnings
  end

  test "junk in a color field is ignored, not written out" do
    css = ThemePalette::Generator.new(Picks.new(brand_color: "#fff; } body { display: none")).css
    assert_equal "", css
  end

  test "the output has no quotes or angle brackets to escape" do
    css = generator(**MATRIX["production"], text_color: "#111111").css
    assert_no_match(/[<>"'&]/, css)
  end

  test "print is light even with dark picks" do
    css = generator(brand_color: "#34b233", background_color: "#101010", surface_color: "#202020", text_color: "#ffffff").css
    print = css[/@media print \{.*\z/m]

    assert_includes print, ":root[data-bs-theme=dark]"
    assert_includes print, "color-scheme: light"
    assert_includes print, "--gp-page: #ebe6d8"
    assert_includes print, "--gp-surface: #fffdf6"
    assert_includes print, "--gp-text: #2b2716"
  end

  test "print keeps light picks" do
    print = generator(background_color: "#fff8e1", surface_color: "#ffffff").css[/@media print \{.*\z/m]

    assert_includes print, "--gp-page: #fff8e1"
    assert_includes print, "--gp-surface: #ffffff"
  end

  test "surface overrides apply to light mode on screen only" do
    css = generator(**MATRIX["production"]).css

    assert_match(/@media screen \{\n:root:not\(\[data-bs-theme=dark\]\) \.card,.*\}.*@media print/m, css)
  end

  test "a light palette on dark picks marks native controls and icons as dark" do
    tokens = generator(surface_color: "#1a1a2e", background_color: "#101018").palette(:light).tokens
    assert_equal "1", tokens["--gp-icon-invert"]
    assert_match(/\A:root \{\n  color-scheme: dark;/, generator(surface_color: "#1a1a2e", background_color: "#101018").css)
  end

  test "a text pick that fails is named and left alone" do
    gen = generator(background_color: "#ffffff", surface_color: "#ffffff", text_color: "#dddddd")

    assert_equal "#dddddd", gen.palette(:light).tokens["--gp-text"]
    assert_includes gen.warnings.join, "Page background"
    assert_includes gen.warnings.join, "Cards and menus"
    assert_includes gen.warnings.join, "1.3:1"
  end

  test "a brand white can't read on is a warning" do
    assert_includes generator(brand_color: "#34b233").warnings.join, "White text is hard to read on Brand"
    assert_empty generator(brand_color: "#6d6753").warnings
  end

  test "custom CSS coloring an editor gets a warning naming the rule" do
    gen = ThemePalette::Generator.new(Picks.new(custom_css: ".cm-editor { background-color: #1b1b1b } .card { color: red }"))

    assert_equal 1, gen.warnings.size
    assert_includes gen.warnings.first, ".cm-editor"

    fine = ThemePalette::Generator.new(Picks.new(custom_css: ".cm-editor { font-size: 12px }"))
    assert_empty fine.warnings
  end

  # -- Staying in step with the skin -------------------------------------------

  def mixin(name)
    Rails.root.join("app/assets/stylesheets/skin/_tokens.scss").read[/@mixin #{name} \{.*?\n\}/m]
  end

  def scss_tokens(name)
    mixin(name).scan(/^\s*(--gp-[a-z-]+):\s*([^;]+);/).to_h
  end

  { light: "light-tokens", dark: "dark-tokens" }.each do |mode, mixin_name|
    test "#{mode} generates every color token the skin defines" do
      palette = generator(**MATRIX["production"]).palette(mode)
      generated = palette.tokens.keys.grep(/\A--gp-/)

      assert_empty scss_tokens(mixin_name).keys - generated, "tokens the generator doesn't produce"
      assert_empty generated - scss_tokens(mixin_name).keys, "tokens the skin doesn't define"
    end

    test "#{mode} defaults match the skin" do
      scss = scss_tokens(mixin_name)
      ThemePalette::Generator::DEFAULTS.fetch(mode).each do |name, value|
        token = "--gp-#{name.to_s.tr("_", "-")}"
        assert_equal value, scss.fetch(token), token
      end
    end

    test "#{mode} default syntax colors read on the editor" do
      scss = scss_tokens(mixin_name)
      backgrounds = %w[--gp-raised --gp-brand-soft].map { |token| Color.parse(scss.fetch(token)) }
      CODE_TOKENS.each do |token|
        backgrounds.each do |background|
          assert_operator Color.parse(scss.fetch(token)).contrast(background), :>=, 4.5, "#{mode} #{token} on #{background}"
        end
      end
    end
  end
end
