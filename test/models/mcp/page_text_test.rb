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
      <template>t</template>
      <div hidden>h</div><span style="display: none">s</span><span class="x d-none">d</span>
      <table><tr><td>shown</td><td hidden>cell</td></tr><tr style="display:none"><td>row</td></tr></table>
    HTML

    assert_equal "| shown |\n| --- |", text(html)
  end

  test "rows in a hidden head, body or foot stay out" do
    html = <<~HTML
      <table>
        <thead hidden><tr><th>head</th></tr></thead>
        <tbody style="display: none"><tr><td>body</td></tr></tbody>
        <tbody class="d-none"><tr><td>classed</td></tr></tbody>
        <tbody><tr><td>shown</td></tr></tbody>
        <tfoot hidden><tr><td>foot</td></tr></tfoot>
      </table>
    HTML

    assert_equal "| shown |\n| --- |", text(html)
  end

  test "a table's caption comes first, unless hidden, and stands alone with no rows" do
    row = "<tr><td>a</td></tr>"

    assert_equal "Hours by week\n\n| a |\n| --- |", text("<table><caption>Hours\n by week</caption>#{row}</table>")
    assert_equal "| a |\n| --- |", text("<table><caption hidden>Hours</caption>#{row}</table>")
    assert_equal "Hours", text("<table><caption>Hours</caption></table>")
    assert_equal "| Inner a |\n| --- |", text("<table><tr><td><table><caption>Inner</caption>#{row}</table></td></tr></table>")
  end

  test "form controls give the value they show" do
    assert_equal "a shown b typed c", text(%(a <input value="shown"> b <textarea>typed</textarea> c))
    assert_equal "a shown", text(%(a <input type="TEXT" value="shown">))
    assert_equal "[x] on [ ] off [x] one [ ] two", text(<<~HTML.squish)
      <input type="checkbox" checked> on <input type="checkbox" value="1"> off
      <input type="radio" checked> one <input type="radio" value="2"> two
    HTML
  end

  test "a select gives the option a browser shows as chosen" do
    options = "<option>first</option><option selected>Chosen  one</option><option>third</option>"

    assert_equal "Chosen one", text("<select>#{options}</select>")
    assert_equal "first", text("<select><option>first</option><option>second</option></select>")
    assert_equal "second", text("<select><option disabled>first</option><optgroup label='g'><option>second</option></optgroup></select>")
    assert_equal "second", text("<select><option selected>first</option><option selected>second</option></select>")
    assert_equal "", text("<select></select>")
    assert_equal "first, second", text("<select multiple><option selected>first</option><option selected>second</option><option>third</option></select>")
    assert_equal "", text("<select multiple><option>first</option></select>")
  end

  test "a control's value stays in its table cell, so an answer can be told from a blank" do
    html = <<~HTML
      <table>
        <tr><th>Name</th><th>Eligible</th></tr>
        <tr><td>Ann</td><td><select><option value="">-</option><option selected>Yes</option><option>No</option></select></td></tr>
        <tr><td>Bo</td><td><select><option value="">-</option><option>Yes</option><option selected>No</option></select></td></tr>
      </table>
    HTML

    assert_equal "| Name | Eligible |\n| --- | --- |\n| Ann | Yes |\n| Bo | No |", text(html)
  end

  test "hidden and password inputs and buttons stay out, as does a hidden control" do
    html = <<~HTML
      kept
      <input type="hidden" value="h"><input type="password" value="p"><input type="PASSWORD" value="p2">
      <input type="submit" value="s"><input type="button" value="b"><input type="reset" value="r"><input type="image" alt="i" value="i"><input type="file" value="f">
      <button>Save</button><input value="v" hidden><select class="d-none"><option>o</option></select><textarea style="display:none">t</textarea>
    HTML

    assert_equal "kept", text(html)
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
