require "test_helper"

# Every rule in the compiled application stylesheet that carries the old primary
# color as a literal has to be redefined by the skin, or that component keeps
# the old color. Catches a new Bootstrap component after an upgrade.
class ModernSkinCoverageTest < ActiveSupport::TestCase
  LITERAL_PRIMARY = /#6d6753|109,\s*103,\s*83/i
  RULE = /([^{}]+)\{([^{}]*)\}/m

  test "the skin redefines every use of the old primary color" do
    literals = rules(compiled("application.css")).flat_map do |selector, body|
      declarations(body).filter_map do |property, value|
        [ component_of(selector), property ] if value.match?(LITERAL_PRIMARY)
      end
    end.uniq

    assert_operator literals.size, :>=, 30, "expected to find the old primary color in the compiled CSS"

    skin = rules(compiled("skin.css")).map { |selector, body| [ selector, declarations(body).map(&:first) ] }
    missing = literals.reject do |component, property|
      skin.any? { |selector, properties| selector.include?(component) && properties.include?(property) }
    end

    assert_empty missing, "the skin doesn't redefine these [component, property] pairs"
  end

  test "the skin has no color literal outside its tokens" do
    sources = Rails.root.glob("app/assets/stylesheets/skin/*.scss").reject { |path| path.basename.to_s == "_tokens.scss" }
    literal = /#[0-9a-f]{3,8}\b|\brgba?\(\s*\d/i

    offenders = sources.flat_map do |path|
      path.readlines.filter_map { |line| "#{path.basename}: #{line.strip}" if line.sub(%r{//.*}, "").match?(literal) }
    end

    assert_empty offenders
  end

  test "!important appears only with a comment saying why" do
    sources = Rails.root.glob("app/assets/stylesheets/skin/*.scss")

    offenders = sources.flat_map do |path|
      lines = path.readlines
      lines.each_with_index.filter_map do |line, index|
        next unless line.include?("!important")
        nearby = lines[[ index - 3, 0 ].max..index].join
        "#{path.basename}:#{index + 1}" unless nearby.include?("//")
      end
    end

    assert_empty offenders
  end

  private

  def compiled(name)
    path = Rails.root.join("app/assets/builds", name)
    assert path.exist?, "#{path} is missing; run yarn build:css"
    path.read.gsub(%r{/\*.*?\*/}m, "")
  end

  def rules(css)
    css.scan(RULE).map { |selector, body| [ selector.strip.gsub(/\s+/, " "), body ] }
  end

  def declarations(body)
    body.split(";").filter_map do |declaration|
      property, value = declaration.split(":", 2).map(&:strip)
      [ property, value ] if property.present? && value.present?
    end
  end

  # ".form-control" from ".form-control:focus, .hw-combobox:focus"; ":root" for
  # the variable blocks.
  def component_of(selector)
    selector.split(",").first[/\.[\w-]+/] || ":root"
  end
end
