# Reads ledgers into the raw rows Gateway::LedgerSource yields. A whole
# ledger is read at a time, because each entry's columns depend on the
# others: ledger payments aren't applied to particular charges, so every
# payment and credit counts against the oldest unpaid charge first (by
# created_at, then id), and what's left after every charge is paid is that
# payment's unapplied amount. The computed amounts go into the rows, so
# normalize still sees one record.
class Accounting::Ledgers::Reader
  attr_reader :source

  def initialize(source)
    @source = source
  end

  # Everything one ledger holds: the customer, the tags its entries carry
  # and the entries, as [entity_type, data] pairs.
  def rows_for(ledger)
    entries = entry_rows(ledger)
    tag_ids = entries.flat_map { |entry| entry["tag_ids"] }.uniq
    tags = LedgerTag.where(id: tag_ids).order(:name, :id).map { |tag| [ "LedgerTag", tag_row(tag) ] }
    [ [ "Ledger", ledger_row(ledger) ], *tags, *entries.map { |entry| [ "LedgerEntry", entry ] } ]
  end

  def ledger_row(ledger)
    owners = ledger.ledger_ownerships.select { |ownership| ownership.owner_type == "Person" }.map(&:owner_id).uniq.sort
    { "id" => ledger.id, "name" => ledger.name, "team_id" => ledger.team_id, "person_owner_ids" => owners, "url" => path(:ledger_path, ledger.id) }
  end

  def tag_row(tag)
    { "id" => tag.id, "name" => tag.name, "url" => path(:ledger_tag_path, tag.id) }
  end

  # The ledger's counted entries, oldest first, each with its role and the
  # amounts oldest-first application gives it. Counted as Ledger#refresh_balance
  # counts them: finalized and not failed. A split's children are counted,
  # and its parent only for what the children don't cover yet (all of it
  # just after Split, which adds two empty children), so the total always
  # matches the ledger's balance.
  def entry_rows(ledger)
    entries = ledger.ledger_entries.order(:created_at, :id).pluck(:id, :parent_id, :amount_cents, :remark, :created_at, :failed, :finalized)
      .map { |id, parent_id, amount, remark, created_at, failed, finalized| { id:, parent_id:, amount:, remark:, created_at:, ok: finalized == true && failed == false } }
    by_id = entries.index_by { |entry| entry[:id] }
    children = entries.select { |entry| entry[:parent_id] }.group_by { |entry| entry[:parent_id] }
    counted = entries.filter_map do |entry|
      next unless entry[:ok] && (entry[:parent_id].nil? || by_id[entry[:parent_id]].nil? || by_id[entry[:parent_id]][:ok])

      if children.key?(entry[:id])
        split = children[entry[:id]].select { |child| child[:ok] }.sum { |child| child[:amount].to_i }
        entry = entry.merge(amount: entry[:amount].to_i - split)
      end
      entry unless entry[:amount].to_i.zero?
    end

    tags = tags_by_entry(counted.map { |entry| entry[:id] })
    rows = counted.map { |entry| entry_row(ledger, entry, tags.fetch(entry[:id], [])) }
    apply_oldest_first(rows)
    rows
  end

  private
    def entry_row(ledger, entry, tags)
      {
        "id" => entry[:id], "ledger_id" => ledger.id, "parent_id" => entry[:parent_id], "amount_cents" => entry[:amount],
        "remark" => entry[:remark], "created_at" => entry[:created_at].utc.iso8601(6),
        "tag_ids" => tags.map(&:first), "first_tag_name" => tags.first&.last,
        "role" => role_for(entry[:amount], tags.map(&:first)),
        "url" => path(:ledger_ledger_entry_path, ledger.id, entry[:id]),
        "pay_url" => (path(:new_ledger_payment_path, ledger_id: ledger.id) if payments?)
      }
    end

    # charge_sign says which way charges go; a payment-side entry carrying a
    # credit tag is a credit.
    def role_for(amount, tag_ids)
      charge = source.charge_sign == "positive" ? amount.positive? : amount.negative?
      return "charge" if charge

      (tag_ids & credit_tag_ids).any? ? "credit" : "payment"
    end

    def apply_oldest_first(rows)
      charges = rows.select { |row| row["role"] == "charge" }
      charges.each { |charge| charge["balance_cents"] = charge["amount_cents"].abs }

      rows.reject { |row| row["role"] == "charge" }.each do |payment|
        left = payment["amount_cents"].abs
        applied = []
        charges.each do |charge|
          break if left.zero?
          next if charge["balance_cents"].zero?

          amount = [ left, charge["balance_cents"] ].min
          charge["balance_cents"] -= amount
          left -= amount
          applied << { "external_id" => charge["id"], "amount_cents" => amount }
        end
        payment["applied_to"] = applied
        payment["unapplied_cents"] = left
      end
    end

    # Each entry's tags as [id, name] pairs, in the order they were added.
    def tags_by_entry(entry_ids)
      return {} if entry_ids.empty?

      LedgerTagging.joins(:ledger_tag).where(ledger_entry_id: entry_ids).order(:created_at, :id)
        .pluck(:ledger_entry_id, :ledger_tag_id, "ledger_tags.name")
        .group_by(&:first).transform_values { |pairs| pairs.map { |_, tag_id, name| [ tag_id, name ] }.uniq(&:first) }
    end

    def credit_tag_ids
      @credit_tag_ids ||= source.credit_tags.map(&:id)
    end

    # Ledgers have a Pay page while a payment gateway exists.
    def payments?
      @payments = Gateway.any_registered?(:payment) if @payments.nil?
      @payments
    end

    # A page in GatherPack, when its route is drawn (the ledger pages are
    # drawn only while the ledger feature is on).
    def path(helper, *args)
      helpers = Rails.application.routes.url_helpers
      helpers.public_send(helper, *args) if helpers.respond_to?(helper)
    end
end
