require "test_helper"

class Mcp::PageTextTest < ActiveSupport::TestCase
  def text(html)
    Mcp::PageText.call(html)
  end

  test "paragraphs, headings and line breaks" do
    assert_equal "Title\n\nOne line\nnext line\n\nTwo words", text("<h1>Title</h1><p>One   line<br>next line</p>\n<p>Two\n  <b>words</b></p>")
  end

  test "divs stand apart" do
    assert_equal "a\n\nb c", text("<div>a</div><div>b <span>c</span></div>")
  end

  test "lists, nested and numbered" do
    assert_equal "- one\n- two\n  1. deep\n  2. deeper", text("<ul><li>one</li><li>two<ol><li>deep</li><li>deeper</li></ol></li></ul>")
  end

  test "a table is a Markdown table" do
    html = "<table><thead><tr><th>Name</th><th>Hours</th></tr></thead><tbody><tr><td>Ann\n Lee</td><td>2</td></tr><tr><td>Bo</td><td>3</td></tr></tbody></table>"

    assert_equal "| Name | Hours |\n| --- | --- |\n| Ann Lee | 2 |\n| Bo | 3 |", text(html)
  end

  test "a table's pipes are escaped, short rows padded and spans kept in their columns" do
    html = "<table><tr><td>a|b</td><td>c</td><td>d</td></tr><tr><td colspan=2>wide</td><td>e</td></tr><tr><td>short</td></tr></table>"

    assert_equal "| a\\|b | c | d |\n| --- | --- | --- |\n| wide |  | e |\n| short |  |  |", text(html)
  end

  test "a table in a cell stays in its cell, and text around a table stays around it" do
    assert_equal "before\n\n| x y |\n| --- |\n\nafter", text("<p>before</p><table><tr><td><table><tr><td>x</td><td>y</td></tr></table></td></tr></table>after")
  end

  test "an empty table is nothing" do
    assert_equal "", text("<table></table>")
    assert_equal "", text("<table><tr></tr></table>")
  end

  test "what a browser doesn't show stays out" do
    html = <<~HTML
      <style>p { color: red }</style><script>alert("x")</script><!-- note -->
      <template>t</template><select><option>opt</option></select><input value="v"><textarea>ta</textarea>
      <div hidden>h</div><span style="display: none">s</span><span class="x d-none">d</span>
      <table><tr><td>shown</td><td hidden>cell</td></tr><tr style="display:none"><td>row</td></tr></table>
    HTML

    assert_equal "| shown |\n| --- |", text(html)
  end

  test "text shown only on wider screens stays in" do
    assert_equal "wide", text(%(<span class="d-none d-md-inline">wide</span>))
  end

  test "pre keeps its layout, entities are decoded, and images give their alt text" do
    assert_equal "a\n   b\n\n1 < 2 & 3\n\nlogo", text("<pre>a\n   b</pre><p>1 &lt; 2 &amp; 3</p><img src='x' alt='logo'>")
  end

  test "broken HTML doesn't stop it" do
    assert_equal "| a |\n| --- |", text("<table><tr><td>a")
  end
end
