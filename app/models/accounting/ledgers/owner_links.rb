# Links each ledger's customer to the people who own the ledger
# (source: ledger_owner), and removes those links when the ownership goes.
# When a ledger's owners include a guardian of another owner, only the ward
# is linked: the guardian already sees the ward's result through
# guardianship, and a link would give them a bill of their own. A link an
# admin removed is remembered as a dismissal and not made again.
class Accounting::Ledgers::OwnerLinks
  attr_reader :source

  def initialize(source)
    @source = source
  end

  # After a sync: brings the links of every ledger customer saved up to
  # date, and removes owner links of ledgers that are gone.
  def after_sync(records)
    records.select { |record| record.entity_type == "Ledger" && !record.deleted? }.each do |customer|
      reconcile(customer.customer_external_id, Array(customer.data["person_owner_ids"]))
    end
    remove_gone
  end

  # Makes the owner links for one ledger match its person owners.
  def reconcile(ledger_id, owner_ids)
    wanted = linkable(owner_ids)
    owner_links = links.where(customer_external_id: ledger_id, source: "ledger_owner")
    owner_links.where.not(person_id: wanted).find_each(&:destroy!)

    taken = links.where(customer_external_id: ledger_id).pluck(:person_id) +
      source.accounting_customer_dismissals.where(customer_external_id: ledger_id).pluck(:person_id)
    (wanted - taken).each do |person_id|
      links.create!(customer_external_id: ledger_id, person_id: person_id, source: "ledger_owner")
    end
  end

  private
    def links
      source.accounting_customer_links
    end

    # The owners, without any who is a guardian of another owner.
    def linkable(owner_ids)
      people = Person.where(id: owner_ids).to_a
      return people.map(&:id) if people.size < 2

      people.reject { |person| (person.wards.map(&:id) & owner_ids).any? }.map(&:id)
    end

    # Owner links whose ledger is no longer a current customer of this source.
    def remove_gone
      current = source.accounting_records.current.where(entity_type: "Ledger").select(:customer_external_id)
      links.where(source: "ledger_owner").where.not(customer_external_id: current).find_each(&:destroy!)
    end
end
