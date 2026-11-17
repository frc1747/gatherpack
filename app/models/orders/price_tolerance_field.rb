# The price tolerance setting as two numbers, a percentage and an amount,
# and back to the text Orders::Config.price_tolerance parses: "10%, 25",
# "10%" or "25". Either number may be blank. A saved text that isn't a
# percentage and/or an amount is #readable? false: the form shows it as
# "Not found" and keeps it until a number or "clear" is posted.
module Orders
  class PriceToleranceField
    NUMBER = /\A\d+(\.\d+)?\z/

    attr_reader :text, :percent, :amount

    def initialize(text)
      @text = text.to_s
      parse
    end

    def readable?
      @readable
    end

    # The text to save for what the form posted (percent, amount, raw and
    # clear), or current when nothing was posted that changes it. Spacing and
    # formatting of an unchanged value is kept.
    def self.text_from(posted, current)
      posted = posted.to_unsafe_h if posted.respond_to?(:to_unsafe_h)
      return posted.to_s unless posted.is_a?(Hash)

      posted = posted.with_indifferent_access
      return current unless valid?(posted)

      percent = clean(posted[:percent])
      amount = clean(posted[:amount])
      field = new(current)
      return posted[:raw].to_s if percent.blank? && amount.blank? && posted[:raw].present? && posted[:clear] != "1"
      return current if field.readable? && same_number?(field.percent, percent) && same_number?(field.amount, amount)

      [ ("#{format_number(percent)}%" if percent.present?), format_number(amount).presence ].compact.join(", ")
    end

    # Whether the posted numbers are numbers (or blank).
    def self.valid?(posted)
      posted = posted.to_unsafe_h if posted.respond_to?(:to_unsafe_h)
      return true unless posted.is_a?(Hash)

      %w[percent amount].all? { |name| (value = clean(posted[name] || posted[name.to_sym])).blank? || value.match?(NUMBER) }
    end

    def self.clean(value)
      value.to_s.strip.delete("$%,")
    end

    def self.same_number?(saved, posted)
      saved.blank? ? posted.blank? : (posted.present? && saved.to_d == posted.to_d)
    end

    def self.format_number(value)
      return "" if value.blank?

      number = value.to_d
      number.frac.zero? ? number.to_i.to_s : number.to_s("F")
    end

    private

    def parse
      @readable = true
      parts = text.split(/[,;]/).map(&:strip).compact_blank
      parts.each do |part|
        number = part.delete("$").sub(/\s*%\z/, "")
        unless number.match?(NUMBER)
          @readable = false
          next
        end
        if part.end_with?("%")
          @readable &&= @percent.nil?
          @percent ||= number
        else
          @readable &&= @amount.nil?
          @amount ||= number
        end
      end
    end
  end
end
