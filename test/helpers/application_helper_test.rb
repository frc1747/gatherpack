require "test_helper"

class ApplicationHelperTest < ActionView::TestCase
  test "contrasting_color picks text color by brightness" do
    assert_equal "#000", contrasting_color("#ffffff")
    assert_equal "#fff", contrasting_color("#000000")
    assert_equal "#6d6753", contrasting_color("#34c233", dark: "#6d6753", light: "#fffdf6")
  end

  test "contrasting_color falls back instead of raising on blank or non-hex colors" do
    [ nil, "", "  ", "red", "#zzz" ].each do |color|
      assert_equal "#000", contrasting_color(color), "for #{color.inspect}"
    end
  end

  test "event_calendar_colors uses the team color" do
    colors = event_calendar_colors(Event.new(team: Team.new(color: "#000000")))
    assert_equal({ background: "#000000", text: "#fffdf6" }, colors)
  end

  test "event_calendar_colors falls back to the default for missing or invalid colors" do
    [ Event.new, Event.new(team: Team.new(color: nil)), Event.new(team: Team.new(color: "red")),
      Event.new(team: Team.new(color: "#fff;position:fixed")) ].each do |event|
      assert_equal ApplicationHelper::DEFAULT_EVENT_COLOR, event_calendar_colors(event)[:background]
    end
  end

  test "md drops raw HTML, event handlers and javascript: links" do
    html = md("<script>window.x=1</script>\n\n<svg onload=alert(1)>\n\n<img src=x onerror=alert(1)>\n\n[a](javascript:alert(1))")

    assert_no_match(/<script|<svg|<img|onload=|onerror=|href="javascript:/, html)
  end

  test "md renders ordinary Markdown" do
    html = md(<<~MARKDOWN)
      # Heading

      Some *emphasis*, **strong** and `inline code`.

      - one
      - two

      1. first

      [site](https://example.com) [plain](http://example.com) [mail](mailto:a@example.com) [page](/teams)
      Visit https://example.org today.

      ![logo](https://example.com/logo.png)

      ```ruby
      puts "hi"
      ```
    MARKDOWN

    assert html.html_safe?
    assert_includes html, "<h1>Heading</h1>"
    assert_includes html, "<em>emphasis</em>"
    assert_includes html, "<strong>strong</strong>"
    assert_includes html, "<code>inline code</code>"
    assert_includes html, "<li>one</li>"
    assert_includes html, "<ol>"
    assert_includes html, %(<a href="https://example.com">site</a>)
    assert_includes html, %(<a href="http://example.com">plain</a>)
    assert_includes html, %(<a href="mailto:a@example.com">mail</a>)
    assert_includes html, %(<a href="/teams">page</a>)
    assert_includes html, %(<a href="https://example.org">https://example.org</a>)
    assert_includes html, %(<img src="https://example.com/logo.png" alt="logo">)
    assert_match %r{<pre><code class="language-ruby">puts (&quot;|")hi(&quot;|")\n</code></pre>}, html
  end

  test "md only uses a fenced code block's language as a language- class" do
    {
      "```{.position-fixed .vw-100}" => %(<code class="language-position-fixed">),
      "```{ruby onclick=x}" => %(<code class="language-ruby">),
      %(```{" onclick=x}) => "<code>",
      "```fixed-top" => %(<code class="language-fixed-top">),
      "```c++" => %(<code class="language-c++">)
    }.each do |fence, code_tag|
      html = md("#{fence}\nYour session expired.\n```")

      assert_includes html, "<pre>#{code_tag}Your session expired.\n</code></pre>", "for #{fence.inspect}"
      assert_no_match(/vw-100|onclick/, html, "for #{fence.inspect}")
    end
  end

  test "md strips unsafe link and image protocols" do
    html = md(<<~MARKDOWN)
      [a](javascript:alert(1)) [b](JaVaScRiPt:alert(1)) [c](&#106;avascript:alert(1))
      [d](java&#x09;script:alert(1)) [e](vbscript:msgbox(1)) [f](data:text/html,<script>alert(1)</script>)
      ![g](javascript:alert(1)) ![h](data:image/svg+xml,<svg onload=alert(1)>)
    MARKDOWN

    assert_no_match(/(href|src)="\s*(javascript|vbscript|data:text|data:image\/svg)/i, html)
    assert_no_match(/onload=/, html)
  end

  test "md keeps relative and tel: links" do
    html = md("[x](/teams) [top](#top) [rel](teams/1) [tel](tel:+15551234) ![i](logo.png)")

    assert_includes html, %(<a href="/teams">x</a>)
    assert_includes html, %(<a href="#top">top</a>)
    assert_includes html, %(<a href="teams/1">rel</a>)
    assert_includes html, %(<a href="tel:+15551234">tel</a>)
    assert_includes html, %(<img src="logo.png" alt="i">)
  end

  test "md treats nil as empty" do
    assert_equal "", md(nil)
  end

  test "hex_color? only accepts a whole hex color" do
    [ "#fff", "#FFFFFF", "#3788d8" ].each { |color| assert hex_color?(color), "for #{color.inspect}" }
    [ nil, "", "fff", "red", "#ffff", "#fff;position:fixed", "#ff0000 ", "#ff0000\n;x" ].each do |color|
      assert_not hex_color?(color), "for #{color.inspect}"
    end
  end

  test "safe_color keeps hex colors and CSS color names" do
    [ "#fff", "#3788d8", "blue", "RebeccaPurple" ].each { |color| assert_equal color, safe_color(color) }
  end

  test "safe_color falls back for anything that could carry other CSS" do
    [ nil, "", "#ff0000;position:fixed;inset:0", "red;position:fixed", "url(https://evil.example)", "blue " ].each do |color|
      assert_nil safe_color(color), "for #{color.inspect}"
      assert_equal "#0dcaf0", safe_color(color, "#0dcaf0"), "for #{color.inspect}"
    end
  end
end
