require "nokogiri"

# Rendered page HTML as plain text, with tables as Markdown tables, for get_page. What
# the page hides from a browser stays out too, and a form control gives the value it
# shows, as that may be all a page says about the answer. Nokogiri is already here through Rails, so
# this needs no gem of its own, and it does only what get_page needs.
module Mcp::PageText
  SKIPPED = %w[button embed head iframe link meta noscript object script style svg template title].freeze
  PARAGRAPHS = %w[blockquote dl fieldset figure h1 h2 h3 h4 h5 h6 p].freeze
  LINES = %w[address article aside center dd details div dt figcaption footer form header legend main nav section summary].freeze
  # Inputs with no value on show: a button's value is its label, and a file input's is unused.
  UNSHOWN_INPUTS = %w[button file hidden image password reset submit].freeze
  HIDDEN_STYLE = /(\A|;)\s*(display\s*:\s*none|visibility\s*:\s*hidden)/i
  # d-none d-md-block shows on a wider screen, so only a plain d-none counts as hidden.
  RESPONSIVE_DISPLAY = /\bd-(sm|md|lg|xl|xxl)-/
  MAX_COLSPAN = 50

  class << self
    def call(html)
      tidy(text_of(Nokogiri::HTML5.fragment(html)))
    end

    private

    def text_of(node, **context)
      node.children.map { |child| node_text(child, **context) }.join
    end

    def node_text(node, preformatted: false, depth: 0, in_cell: false)
      return node.text? ? text_node(node, preformatted) : "" unless node.element?
      return "" if hidden?(node)

      context = { preformatted:, depth:, in_cell: }
      case node.name
      when "br" then "\n"
      when "hr" then "\n\n"
      when "img" then node["alt"].to_s
      when "input" then input_text(node)
      when "select" then select_text(node)
      when "textarea" then node.text
      when "pre" then "\n\n#{text_of(node, **context, preformatted: true)}\n\n"
      when "table" then in_cell ? " #{[ caption(node), *table_rows(node).flatten ].compact_blank.join(" ")} " : "\n\n#{table(node)}\n\n"
      when "ul", "ol" then "\n#{list(node, context)}\n"
      when *PARAGRAPHS then "\n\n#{text_of(node, **context)}\n\n"
      when *LINES then "\n#{text_of(node, **context)}\n"
      else text_of(node, **context)
      end
    end

    def text_node(node, preformatted)
      preformatted ? node.text : node.text.gsub(/\s+/, " ")
    end

    def hidden?(node)
      return true if SKIPPED.include?(node.name) || node.key?("hidden") || node["style"].to_s.match?(HIDDEN_STYLE)

      classes = node["class"].to_s
      classes.split.include?("d-none") && !classes.match?(RESPONSIVE_DISPLAY)
    end

    def input_text(node)
      type = node["type"].to_s.downcase
      return "" if UNSHOWN_INPUTS.include?(type)
      return node.key?("checked") ? "[x]" : "[ ]" if %w[checkbox radio].include?(type)

      node["value"].to_s
    end

    # What a browser shows as chosen: of several marked selected the last, and of none the
    # first option that can be chosen, unless it's a multiple select, which may have none.
    def select_text(node)
      options = node.css("option")
      selected = options.select { |option| option.key?("selected") }
      chosen = node.key?("multiple") ? selected : [ selected.last || options.find { |option| !option.key?("disabled") } ].compact
      chosen.map { |option| option.text.gsub(/\s+/, " ").strip }.join(", ")
    end

    def list(node, context)
      items = node.element_children.select { |child| child.name == "li" && !hidden?(child) }
      items.each_with_index.map do |item, index|
        marker = node.name == "ol" ? "#{index + 1}." : "-"
        "#{"  " * context[:depth]}#{marker} #{text_of(item, **context, depth: context[:depth] + 1).strip}"
      end.join("\n")
    end

    def table(node)
      [ caption(node), table_markdown(table_rows(node)) ].compact_blank.join("\n\n")
    end

    def caption(node)
      element = node.at_xpath("./caption")
      element && !hidden?(element) ? text_of(element, in_cell: true).gsub(/\s+/, " ").strip : ""
    end

    def table_markdown(rows)
      return "" if rows.empty?

      width = rows.map(&:size).max
      rows = rows.map { |row| (row + Array.new(width - row.size, "")).map { |cell| cell.gsub("|", "\\|") } }
      [ rows.first, Array.new(width, "---"), *rows.drop(1) ].map { |row| "| #{row.join(" | ")} |" }.join("\n")
    end

    # Each row's cells as text, a colspan's extra columns blank. A table in a cell flattens
    # to its cells' text, as Markdown has no nested tables.
    def table_rows(node)
      rows = node.xpath("./tr | ./thead/tr | ./tbody/tr | ./tfoot/tr").reject { |row| hidden?(row) || hidden?(row.parent) }
      rows.map { |row| table_row(row) }.reject(&:empty?)
    end

    def table_row(row)
      row.xpath("./th | ./td").reject { |cell| hidden?(cell) }.flat_map do |cell|
        [ text_of(cell, in_cell: true).gsub(/\s+/, " ").strip, *Array.new(cell["colspan"].to_i.clamp(1, MAX_COLSPAN) - 1, "") ]
      end
    end

    def tidy(text)
      text.gsub(/[ \t]+\n/, "\n").gsub(/\n (?=\S)/, "\n").gsub(/\n{3,}/, "\n\n").strip
    end
  end
end
