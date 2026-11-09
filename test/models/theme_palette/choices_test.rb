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

  test "imports the mapped variables and clears them" do
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
    assert_nil @theme.css_variables
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
end
