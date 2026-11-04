require "nokogiri"

# Rendered page HTML as plain text, with tables as Markdown tables, for get_page. What
# the page hides from a browser stays out too. Nokogiri is already here through Rails, so
# this needs no gem of its own, and it does only what get_page needs.
module Mcp::PageText
  SKIPPED = %w[button embed head iframe input link meta noscript object script select style svg template textarea title].freeze
  PARAGRAPHS = %w[blockquote dl fieldset figure h1 h2 h3 h4 h5 h6 p].freeze
  LINES = %w[address article aside caption center dd details div dt figcaption footer form header legend main nav section summary].freeze
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
      when "pre" then "\n\n#{text_of(node, **context, preformatted: true)}\n\n"
      when "table" then in_cell ? " #{table_rows(node).flatten.join(" ")} " : "\n\n#{table(node)}\n\n"
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

    def list(node, context)
      items = node.element_children.select { |child| child.name == "li" && !hidden?(child) }
      items.each_with_index.map do |item, index|
        marker = node.name == "ol" ? "#{index + 1}." : "-"
        "#{"  " * context[:depth]}#{marker} #{text_of(item, **context, depth: context[:depth] + 1).strip}"
      end.join("\n")
    end

    def table(node)
      rows = table_rows(node)
      return "" if rows.empty?

      width = rows.map(&:size).max
      rows = rows.map { |row| (row + Array.new(width - row.size, "")).map { |cell| cell.gsub("|", "\\|") } }
      [ rows.first, Array.new(width, "---"), *rows.drop(1) ].map { |row| "| #{row.join(" | ")} |" }.join("\n")
    end

    # Each row's cells as text, a colspan's extra columns blank. A table in a cell flattens
    # to its cells' text, as Markdown has no nested tables.
    def table_rows(node)
      rows = node.xpath("./tr | ./thead/tr | ./tbody/tr | ./tfoot/tr").reject { |row| hidden?(row) }
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
