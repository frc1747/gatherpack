# Reads and writes the structured orders settings (approval steps, paid-with
# choices and price tolerance) from form fields, so admins don't edit JSON.
# #save checks what it's given and leaves the settings alone when anything is
# wrong.
module Orders
  class SettingsEditor
    BLANK_ROWS = 2

    attr_reader :steps, :paid_with, :tolerance_percent, :tolerance_amount, :errors

    def initialize
      @errors = []
      load_current
    end

    # Rows for the form: the current ones, then blank ones to fill in.
    def step_rows
      steps + Array.new(BLANK_ROWS) { { "key" => "", "name" => "", "minimum" => "", "approvers" => "" } }
    end

    def paid_with_rows
      paid_with + Array.new(BLANK_ROWS) { { "label" => "", "reimburse" => false } }
    end

    def assign(params)
      @steps = rows(params[:steps]).filter_map { |row| step_from(row) }
      @paid_with = rows(params[:paid_with]).filter_map { |row| paid_with_from(row) }
      @tolerance_percent = params[:tolerance_percent].to_s.strip
      @tolerance_amount = params[:tolerance_amount].to_s.strip
      self
    end

    def save
      validate
      return false if errors.any?

      Settings[:orders_approval_steps] = JSON.generate(steps.map { |step| step.merge("minimum" => step["minimum"].to_d.to_f, "approvers" => approver_lines(step)) })
      Settings[:orders_paid_with] = JSON.generate(paid_with)
      Settings[:orders_price_tolerance] = tolerance_text
      true
    end

    private

    def load_current
      @steps = Orders::Config.approval_steps.map do |step|
        { "key" => step.key, "name" => step.name, "minimum" => format("%g", step.minimum_cents / 100.0), "approvers" => step.approvers.join("\n") }
      end
      @paid_with = Orders::Config.paid_with.map { |choice| { "label" => choice.label, "reimburse" => choice.reimburse } }
      tolerance = Orders::Config.price_tolerance
      @tolerance_percent = format("%g", tolerance.percent)
      @tolerance_amount = format("%g", tolerance.amount_cents / 100.0)
    end

    def rows(value)
      (value.respond_to?(:values) ? value.values : Array(value)).map { |row| row.respond_to?(:to_unsafe_h) ? row.to_unsafe_h : row.to_h }
    end

    def step_from(row)
      name = row["name"].to_s.strip
      return nil if name.blank?

      { "key" => row["key"].to_s.strip, "name" => name, "minimum" => row["minimum"].to_s.strip.presence || "0", "approvers" => row["approvers"].to_s }
    end

    def paid_with_from(row)
      label = row["label"].to_s.strip
      return nil if label.blank?

      { "label" => label, "reimburse" => ActiveModel::Type::Boolean.new.cast(row["reimburse"]) || false }
    end

    def validate
      @errors = []
      errors << "Keep at least one approval step." if steps.empty?
      errors << "Keep at least one way a purchase can be paid." if paid_with.empty?
      assign_keys
      steps.each { |step| validate_step(step) }
      errors << "Price tolerance percentage must be a number." unless number?(tolerance_percent)
      errors << "Price tolerance amount must be a number." unless number?(tolerance_amount)
    end

    # New steps get a key from their name that no other step has and no
    # approval on record uses, so a removed step's approvals never pass to a
    # new one. A key never changes once used, since approvals are stored by it.
    def assign_keys
      taken = steps.pluck("key").compact_blank | OrderApproval.distinct.pluck(:step_key) | OrderRequestEvent.where.not(step_key: nil).distinct.pluck(:step_key)
      steps.each do |step|
        next if step["key"].present?

        base = step["name"].parameterize(separator: "_").presence || "step"
        key = base
        number = 1
        key = "#{base}_#{number += 1}" while taken.include?(key)
        step["key"] = key
        taken << key
      end
      dupes = steps.pluck("key").tally.select { |_key, count| count > 1 }.keys
      errors << "Each approval step needs its own key (#{dupes.to_sentence} is repeated)." if dupes.any?
    end

    def validate_step(step)
      errors << "#{step['name']}: the minimum must be a number of dollars, zero or more." unless number?(step["minimum"])
      approver_lines(step).each do |line|
        badge_name, team_name = line.split(">", 2).map(&:strip)
        errors << "#{step['name']}: no badge given in \"#{line}\"." if badge_name.blank?
        errors << "#{step['name']}: no badge named \"#{badge_name}\" that admins assign." if badge_name.present? && !Badge.added_by_admin.exists?([ "LOWER(name) = ?", badge_name.downcase ])
        errors << "#{step['name']}: no team named \"#{team_name}\"." if team_name.present? && !Team.exists?(name: team_name)
      end
    end

    def approver_lines(step)
      step["approvers"].to_s.lines.map(&:strip).compact_blank
    end

    def number?(text)
      text.to_s.strip.match?(/\A\d+(\.\d+)?\z/)
    end

    def tolerance_text
      # Zeros are written out: a blank setting means the default.
      [ "#{plain(tolerance_percent)}%", plain(tolerance_amount) ].join(", ")
    end

    def plain(text)
      text.to_d.to_f.to_s.delete_suffix(".0")
    end
  end
end
