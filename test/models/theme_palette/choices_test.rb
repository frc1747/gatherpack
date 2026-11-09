require "test_helper"

class ThemePaletteChoicesTest < ActiveSupport::TestCase
  setup { @theme = Theme.instance }

  test "accepts #rrggbb and blank, and normalizes" do
    @theme.brand_color = "#AABBCC"
    @theme.background_color = ""
    assert @theme.valid?
    assert_equal "#aabbcc", @theme.brand_color
    assert_nil @theme.background_color
  end

  %w[#abc red #gggggg #12345678 #123456;x #fff;}body{display:none].each do |bad|
    test "rejects #{bad}" do
      @theme.brand_color = bad
      assert_not @theme.valid?
      assert_includes @theme.errors[:brand_color].join, "hex color"
    end
  end

  test "each field is validated" do
    ThemePalette::FIELDS.each do |field|
      @theme[field] = "nope"
      assert_not @theme.valid?, field
      assert @theme.errors[field].any?, field
      @theme[field] = nil
    end
  end

  test "imports the mapped variables and keeps the rest" do
    @theme.update!(css_variables: <<~CSS)
      --bs-primary: #34b233;
      --bs-body-bg: #505050 !important;
      --bs-card-bg: #c8c8c8;
      --pair-a-bg: #ffffff;
    CSS

    @theme.use_css_variables_as_colors!

    assert_equal "#34b233", @theme.brand_color
    assert_equal "#505050", @theme.background_color
    assert_equal "#c8c8c8", @theme.surface_color
    assert_nil @theme.text_color
    assert_equal "--pair-a-bg: #ffffff;", @theme.css_variables
  end

  test "clears the variables when every one was imported" do
    @theme.update!(css_variables: "--bs-primary: #34b233;\n--bs-body-bg: #505050;")
    result = @theme.use_css_variables_as_colors!

    assert_nil @theme.css_variables
    assert_equal "Imported --bs-primary and --bs-body-bg.", result.summary
  end

  test "imports a readable text color" do
    @theme.update!(css_variables: "--bs-body-bg: #ffffff;\n--bs-card-bg: #eeeeee;\n--bs-body-color: #222222;")
    @theme.use_css_variables_as_colors!

    assert_equal "#222222", @theme.text_color
  end

  test "leaves out a text color that wouldn't be readable" do
    @theme.update!(css_variables: "--bs-body-bg: #505050;\n--bs-card-bg: #c8c8c8;\n--bs-body-color: #1b1b1b;")
    @theme.use_css_variables_as_colors!

    assert_nil @theme.text_color
    assert_nil @theme.css_variables
  end

  test "expands short hex and ignores anything else" do
    @theme.update!(css_variables: "--bs-primary: #abc;\n--bs-body-bg: rgb(0, 0, 0);\n--bs-card-bg: var(--x);")
    @theme.use_css_variables_as_colors!

    assert_equal "#aabbcc", @theme.brand_color
    assert_nil @theme.background_color
    assert_nil @theme.surface_color
  end

  test "reads several variables on one line" do
    @theme.update!(css_variables: "--bs-primary: #34b233; --bs-body-bg: #505050;")
    @theme.use_css_variables_as_colors!

    assert_equal "#34b233", @theme.brand_color
    assert_equal "#505050", @theme.background_color
    assert_nil @theme.css_variables
  end

  test "reads past comments" do
    @theme.update!(css_variables: "--bs-primary: #34b233; /* team green */\n/* --bs-card-bg: #000000; */")
    @theme.use_css_variables_as_colors!

    assert_equal "#34b233", @theme.brand_color
    assert_nil @theme.surface_color
    assert_nil @theme.css_variables
  end

  test "reads lines with no semicolon, as the field's placeholder shows" do
    @theme.update!(css_variables: "--bs-primary: #34b233\n--bs-body-bg: #505050")
    @theme.use_css_variables_as_colors!

    assert_equal "#34b233", @theme.brand_color
    assert_equal "#505050", @theme.background_color
  end

  [ "rgb(52, 178, 51)", "white", "var(--team)" ].each do |value|
    test "keeps a mapped variable set to #{value} and writes nothing" do
      original = "--bs-primary: #{value};"
      @theme.update!(css_variables: original)

      result = @theme.use_css_variables_as_colors!

      assert_equal original, @theme.reload.css_variables
      assert_nil @theme.brand_color
      assert_equal "No colors were imported. Still in your CSS variables: --bs-primary.", result.summary
    end
  end

  test "imports what it can read and names what stayed" do
    @theme.update!(css_variables: "--bs-primary: #34b233;\n--bs-body-bg: rgb(0, 0, 0);\n--bs-font-sans-serif: Inter;\nnot a declaration")

    result = @theme.use_css_variables_as_colors!

    assert_equal "#34b233", @theme.brand_color
    assert_equal "--bs-body-bg: rgb(0, 0, 0);\n--bs-font-sans-serif: Inter;\nnot a declaration;", @theme.css_variables
    assert_equal "Imported --bs-primary. Still in your CSS variables: --bs-body-bg, --bs-font-sans-serif, and not a declaration.", result.summary
  end

  test "a semicolon inside parentheses stays part of the value" do
    @theme.update!(css_variables: "--bs-primary: #34b233;\n--logo: url(data:image/png;base64,AAAA);")
    @theme.use_css_variables_as_colors!

    assert_equal "--logo: url(data:image/png;base64,AAAA);", @theme.css_variables
  end

  test "says when a text color was left out" do
    @theme.update!(css_variables: "--bs-body-bg: #505050;\n--bs-card-bg: #c8c8c8;\n--bs-body-color: #1b1b1b;")

    assert_includes @theme.use_css_variables_as_colors!.summary, "Left out --bs-body-color"
  end

  test "judges an imported text color against colors already saved" do
    @theme.update!(background_color: "#000000", css_variables: "--bs-body-color: #111111;")

    result = @theme.use_css_variables_as_colors!

    assert_nil @theme.text_color
    assert_includes result.summary, "Left out --bs-body-color"
  end

  test "a long list of what stayed is cut short for the flash" do
    @theme.update!(css_variables: (1..30).map { |number| "--custom-#{number}: 1;" }.join("\n"))

    summary = @theme.use_css_variables_as_colors!.summary

    assert_includes summary, "22 more"
    assert_not_includes summary, "--custom-30"
    assert_equal 30, @theme.reload.css_variables.lines.size
  end
end
