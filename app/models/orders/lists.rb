# The managed lists orders keeps (payment methods, delivery problem kinds
# and approval steps): their starting rows, and turning what orders stored
# before they were lists (the orders_paid_with and orders_approval_steps
# settings, the text a purchase was paid with) into rows. The migrations
# that made the lists use the conversions; each is safe to run again.
module Orders
  module Lists
    PAYMENT_METHODS = [
      { name: "Team card", reimburse: false },
      { name: "Paid personally", reimburse: true }
    ].freeze

    DELIVERY_PROBLEM_KINDS = [
      { name: "Damaged", key: "damaged" },
      { name: "Wrong item", key: "wrong_item" }
    ].freeze

    APPROVAL_STEPS = [ { name: "Approval", key: "approval", minimum_cents: 0 } ].freeze

    # What orders_paid_with held until it was changed. Its two choices aren't
    # added as rows: the defaults above stand in for them.
    OLD_DEFAULT_PAID_WITH = [
      { "label" => "Team card", "reimburse" => false },
      { "label" => "Personal card — reimburse", "reimburse" => true }
    ].freeze

    module_function

    # Fills any of the lists that is empty with its starting rows.
    def seed!
      PaymentMethod.seed_defaults!(PAYMENT_METHODS)
      seed_delivery_problem_kinds!
      ApprovalStep.seed_defaults!(APPROVAL_STEPS)
    end

    def seed_delivery_problem_kinds!
      DeliveryProblemKind.seed_defaults!(DELIVERY_PROBLEM_KINDS)
      DELIVERY_PROBLEM_KINDS.each do |row|
        DeliveryProblemKind.create!(row) unless DeliveryProblemKind.exists?(key: row[:key])
      end
    end

    # The defaults, then each choice in the saved setting (unless it is the
    # old default) and each text a purchase was paid with, then points every
    # purchase at its row. A choice keeps its reimburse flag; a text that
    # was never a choice reimburses when its purchases named someone to pay
    # back. Reads purchases.paid_with, so run it before that column goes.
    def convert_payment_methods!(stored)
      PaymentMethod.seed_defaults!(PAYMENT_METHODS)
      choices = parse_json(stored).select { |entry| entry.is_a?(Hash) && entry["label"].to_s.strip.present? }
      reimburse = choices.to_h { |entry| [ entry["label"].to_s.strip.downcase, ActiveModel::Type::Boolean.new.cast(entry["reimburse"]) || false ] }
      choices = [] if choices == OLD_DEFAULT_PAID_WITH

      texts = connection.select_rows(<<~SQL.squish)
        SELECT TRIM(paid_with), BOOL_OR(reimburse_to_id IS NOT NULL) FROM purchases
        WHERE TRIM(COALESCE(paid_with, '')) <> '' GROUP BY TRIM(paid_with) ORDER BY MIN(created_at)
      SQL
      wanted = choices.map { |entry| [ entry["label"].to_s.strip, nil ] } + texts
      wanted.each do |name, paid_back|
        next if PaymentMethod.where("LOWER(name) = ?", name.downcase).exists?

        PaymentMethod.create!(name: name, reimburse: reimburse.fetch(name.downcase) { paid_back || false })
      end

      connection.execute(<<~SQL.squish)
        UPDATE purchases SET payment_method_id = payment_methods.id FROM payment_methods
        WHERE purchases.payment_method_id IS NULL AND LOWER(TRIM(purchases.paid_with)) = LOWER(payment_methods.name)
      SQL
    end

    # One row per step in the saved setting, keeping its key, name and
    # minimum, with an approver row per "Badge name > Team name" line. Lines
    # whose badge or team isn't found reached nobody, so they're left out
    # and returned as "Step: line". A blank or unreadable setting gives the
    # default step. Does nothing when there are steps already.
    def convert_approval_steps!(stored)
      return [] if ApprovalStep.exists?

      entries = parse_json(stored).select { |entry| entry.is_a?(Hash) && entry["key"].present? }
      skipped = []
      ApprovalStep.transaction do
        if entries.empty?
          ApprovalStep.seed_defaults!(APPROVAL_STEPS)
          next
        end

        entries.uniq { |entry| entry["key"].to_s }.each_with_index do |entry, index|
          step = ApprovalStep.create!(key: entry["key"].to_s, position: index,
            name: free_step_name(entry["name"].presence || entry["key"].to_s.humanize),
            minimum_cents: (entry["minimum"].to_d * 100).round)
          Array(entry["approvers"]).map { |line| line.to_s.strip }.compact_blank.uniq.each do |line|
            badge, team = grant(line)
            if badge.nil? || team == :missing
              skipped << "#{step.name}: #{line}"
            elsif !step.approvers.exists?(badge: badge, team: team)
              step.approvers.create!(badge: badge, team: team)
            end
          end
        end
      end
      skipped
    end

    # [badge, team] for a "Badge name > Team name" line: team nil for every
    # team, :missing when it names a team that isn't found. Admin-assigned
    # badges first, since only they count.
    def grant(line)
      badge_name, team_name = line.split(">", 2).map(&:strip)
      return [ nil, nil ] if badge_name.blank?

      badge = Badge.added_by_admin.find_by("LOWER(name) = ?", badge_name.downcase) ||
        Badge.find_by("LOWER(name) = ?", badge_name.downcase)
      team = team_name.present? ? (Team.find_by(name: team_name) || :missing) : nil
      [ badge, team ]
    end

    # The settings these lists replace, as the old readers took them, for
    # undoing the migrations.
    def payment_methods_json
      JSON.generate(PaymentMethod.ordered.map { |method| { "label" => method.name, "reimburse" => method.reimburse } })
    end

    def approval_steps_json
      steps = ApprovalStep.active.ordered.includes(approvers: %i[badge team]).map do |step|
        minimum = step.minimum_cents / 100r
        { "key" => step.key, "name" => step.name, "minimum" => minimum.denominator == 1 ? minimum.to_i : minimum.to_f,
          "approvers" => step.approvers.map(&:line) }
      end
      JSON.generate(steps)
    end

    # The saved text of a setting, read from the store whether or not
    # anything registers it any more.
    def stored_setting(key)
      Settings.instance.stored_values[key]
    end

    def forget_setting(key)
      store = Settings.instance.store
      store.transaction { store.delete(key) }
    end

    def restore_setting(key, value)
      store = Settings.instance.store
      store.transaction { store[key] = value }
    end

    def parse_json(text)
      return [] if text.blank?

      Array(JSON.parse(text))
    rescue JSON::ParserError
      []
    end

    def free_step_name(name)
      return name unless ApprovalStep.where("LOWER(name) = ?", name.downcase).exists?

      number = 2
      number += 1 while ApprovalStep.where("LOWER(name) = ?", "#{name} #{number}".downcase).exists?
      "#{name} #{number}"
    end

    def connection
      ActiveRecord::Base.connection
    end
  end
end
