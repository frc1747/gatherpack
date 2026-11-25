# Links between a source's customers and GatherPack people: suggestions,
# the automatic links an exact reference makes, dismissals and the parent
# rollup. Reads only the neutral columns of customer records, so it works
# the same on every source.
class Accounting::CustomerLinks
  # Ways a customer is matched to people, in the order a source tries them.
  #   reference: the customer's reference holds a person's GatherPack id
  #              (anywhere in the text) or is an account email; linked
  #              automatically when exact and unique.
  #   name:      the customer's name is a person's name, ignoring case,
  #              punctuation and accents, "Last, First" too. Exact when it
  #              is the name they go by (their display name) and nobody
  #              else's; only their legal first and last name is a
  #              "legal name match", suggested but never exact.
  #   email:     the customer's email is a person's account email; that
  #              person's wards are suggested too.
  STRATEGIES = %w[ reference name email ].freeze
  DEFAULT_STRATEGIES = %w[ name email ].freeze

  # A person's GatherPack id inside free text, such as a customer's notes:
  # the prefix and the neat-id characters (lowercase letters and digits).
  PERSON_ID_TOKEN = /(?<![a-z0-9_])per_[a-z0-9]+/

  # A person a customer may be for, with the words saying why. Confirmed:
  # an exact name match that the customer's email backs up too (the person
  # owns the email or is a ward of whoever does).
  Suggestion = Data.define(:person, :strategy, :reason, :exact, :confirmed) do
    def initialize(person:, strategy:, reason:, exact:, confirmed: false)
      super
    end
  end

  attr_reader :source

  def initialize(source)
    @source = source
  end

  def strategies
    source.match_strategy_list
  end

  def rollup?
    source.customer_rollup?
  end

  # The source's current customer records.
  def customers
    source.accounting_records.current.where(role: "customer")
  end

  def links
    source.accounting_customer_links
  end

  def dismissals
    source.accounting_customer_dismissals
  end

  # Suggestions for each customer record, by customer_external_id, in the
  # order of the source's strategies. People already linked to the customer
  # or dismissed for it are left out.
  def suggestions_for(customer_records)
    suggest(customer_records, strategies)
  end

  # Links the customers whose reference matches exactly one person, unless
  # that pair was dismissed or is linked already. Returns the links made.
  # Only the reference strategy runs, so the source's order of strategies
  # doesn't matter and no other lookups are made.
  def link_exact_references(customer_records)
    return [] unless strategies.include?("reference")

    suggest(customer_records, [ "reference" ]).flat_map do |customer_external_id, found|
      found.select(&:exact).map { |suggestion| link!(customer_external_id, suggestion.person, source: "reference") }
    end
  end

  # Links every customer that has no link yet to the one person whose name
  # matches it exactly. Returns the links made. Only the name strategy
  # runs, so a person another strategy found first still counts.
  def link_exact_names(customer_records, created_by: nil)
    return [] unless strategies.include?("name")

    unlinked = customer_records.to_a.reject { |customer| covered?(customer.customer_external_id) }
    suggest(unlinked, [ "name" ]).filter_map do |customer_external_id, found|
      exact = found.select(&:exact)
      link!(customer_external_id, exact.first.person, source: "confirmed", created_by: created_by) if exact.one?
    end
  end

  # After a sync saved records: makes the automatic links for the customers
  # among them, then fires "accounting - customer unlinked" for each new
  # customer still not linked to anyone.
  def after_sync(records)
    saved = records.select { |record| record.role == "customer" && !record.deleted? }
    return if saved.empty?

    link_exact_references(saved)
    hooks = Hook.where(event: "accounting - customer unlinked").to_a
    return if hooks.empty?

    linked_ids = links.distinct.pluck(:customer_external_id)
    saved.select(&:previously_new_record?).each do |customer|
      id = customer.customer_external_id
      next if linked_ids.include?(id) || rolled_up_into(id, linked_ids)

      hooks.each { |hook| hook.run(customer) }
    end
  end

  # Links a customer to a person (again, if it was dismissed). Returns the
  # link, or the one already there. A new link queues the source's rules
  # for that person.
  def link!(customer_external_id, person, source:, created_by: nil)
    link = AccountingCustomerLink.transaction do
      dismissals.where(customer_external_id: customer_external_id, person: person).delete_all
      links.find_by(customer_external_id: customer_external_id, person: person) ||
        links.create!(customer_external_id: customer_external_id, person: person, source: source, created_by: created_by)
    end
    Accounting::EvaluateRuleJob.for_source(self.source, [ person.id ]) if link.previously_new_record?
    link
  end

  # Removes a link and remembers the pair as dismissed, so neither a
  # suggestion nor an automatic link brings it back. Queues the source's
  # rules for that person.
  def unlink!(link)
    AccountingCustomerLink.transaction do
      dismiss!(link.customer_external_id, link.person)
      link.destroy!
    end
    Accounting::EvaluateRuleJob.for_source(source, [ link.person_id ])
  end

  def dismiss!(customer_external_id, person)
    dismissals.find_or_create_by!(customer_external_id: customer_external_id, person: person)
  end

  # The customers whose records count for a person: the ones linked to them,
  # and with the parent rollup every sub-customer below those.
  def customer_ids_for(person)
    ids = links.where(person: person).pluck(:customer_external_id).uniq
    rollup? ? (ids + descendants_of(ids)).uniq : ids
  end

  # The people a customer's records count for: those linked to it, and with
  # the parent rollup those linked to any customer above it.
  def people_for(customer_external_id)
    ids = [ customer_external_id ]
    ids += ancestors_of(customer_external_id) if rollup?
    Person.where(id: links.where(customer_external_id: ids).select(:person_id))
  end

  # Whether a customer's records count for anyone.
  def covered?(customer_external_id)
    people_for(customer_external_id).exists?
  end

  # With the parent rollup, the nearest linked customer above this one, if
  # any. linked_ids: the linked customers' ids, when the caller has them.
  def rolled_up_into(customer_external_id, linked_ids = nil)
    return nil unless rollup?

    linked_ids ||= links.distinct.pluck(:customer_external_id)
    ancestors_of(customer_external_id).find { |id| linked_ids.include?(id) }
  end

  # Turns a name into the form names are compared in: accents, case and
  # punctuation dropped, "Last, First" turned round.
  def self.comparable_name(text)
    text = text.to_s
    last, first = text.split(",", 2)
    text = "#{first} #{last}" if first.present?
    ActiveSupport::Inflector.transliterate(text).downcase.gsub(/[^a-z0-9\s]/, "").squish
  end

  private
    # Suggestions from the given strategies for each customer record, by
    # customer_external_id, without pairs already linked or dismissed.
    def suggest(customer_records, chosen)
      customer_records = customer_records.to_a
      ids = customer_records.map(&:customer_external_id)
      taken = pairs(links.where(customer_external_id: ids)) + pairs(dismissals.where(customer_external_id: ids))
      matcher = Matcher.new(customer_records, chosen)

      customer_records.to_h do |customer|
        found = matcher.suggestions(customer).reject { |suggestion| taken.include?([ customer.customer_external_id, suggestion.person.id ]) }
        [ customer.customer_external_id, found ]
      end
    end

    def pairs(relation)
      relation.pluck(:customer_external_id, :person_id).to_set
    end

    def parents
      @parents ||= customers.where.not(parent_external_id: nil).pluck(:customer_external_id, :parent_external_id).to_h
    end

    def ancestors_of(customer_external_id)
      found = []
      current = parents[customer_external_id]
      while current && !found.include?(current) && current != customer_external_id
        found << current
        current = parents[current]
      end
      found
    end

    def descendants_of(ids)
      children = parents.each_with_object(Hash.new { |hash, key| hash[key] = [] }) { |(child, parent), tree| tree[parent] << child }
      found = []
      queue = ids.dup
      while (id = queue.shift)
        children[id].each do |child|
          next if found.include?(child) || ids.include?(child)

          found << child
          queue << child
        end
      end
      found
    end

    # Finds people for a batch of customer records, looking people up once
    # for the whole batch.
    class Matcher
      def initialize(customer_records, strategies)
        @customers = customer_records
        @strategies = strategies
      end

      def suggestions(customer)
        found = @strategies.flat_map { |strategy| send(strategy, customer) }
        found = confirm_by_email(found)
        found.sort_by.with_index { |suggestion, index| [ suggestion.confirmed ? 0 : 1, index ] }.uniq { |suggestion| suggestion.person.id }
      end

      private
        def reference(customer)
          value = customer.reference.to_s.strip
          return [] if value.blank?

          tokens = value.downcase.scan(PERSON_ID_TOKEN).uniq
          people = if tokens.any?
            # The id may sit anywhere in the text (a customer's notes). Two
            # different ids mean a customer for several people: no match.
            tokens.one? ? [ person_by_neat_id(tokens.first) ].compact : []
          else
            people_by_email.fetch(value.downcase, [])
          end
          people.map { |person| Suggestion.new(person: person, strategy: "reference", reason: "reference match", exact: people.one?) }
        end

        def name(customer)
          key = Accounting::CustomerLinks.comparable_name(customer.name)
          people = key.present? ? people_by_name.fetch(key, []) : []
          people.map do |person|
            # Matching only the legal first and last name of someone who goes
            # by another name could be anyone, such as a relative.
            legal_only = legal_only_names.include?([ key, person.id ])
            Suggestion.new(person: person, strategy: "name", reason: legal_only ? "legal name match" : "name match", exact: people.one? && !legal_only)
          end
        end

        # Puts an exact name match first, as "name and email match", when
        # the customer's email also points at that person or at their
        # guardian. Only when both strategies ran.
        def confirm_by_email(found)
          emailed = found.select { |suggestion| suggestion.strategy == "email" }.map { |suggestion| suggestion.person.id }
          return found if emailed.empty?

          found.map do |suggestion|
            next suggestion unless suggestion.strategy == "name" && suggestion.exact && emailed.include?(suggestion.person.id)

            Suggestion.new(person: suggestion.person, strategy: "name", reason: "name and email match", exact: true, confirmed: true)
          end
        end

        def email(customer)
          people = people_by_email.fetch(customer.email.to_s.strip.downcase, [])
          people.flat_map do |person|
            wards = wards_of(person).map do |ward|
              Suggestion.new(person: ward, strategy: "email", reason: "ward of #{person.identifier_name} (email match)", exact: false)
            end
            [ Suggestion.new(person: person, strategy: "email", reason: "email match", exact: false), *wards ]
          end
        end

        def person_by_neat_id(value)
          Person.find_by_neat_id(value)
        rescue StandardError
          nil
        end

        # Account emails named by the batch's customers, lowercased, to the
        # people signing in with them.
        def people_by_email
          @people_by_email ||= begin
            emails = @customers.flat_map { |customer| [ customer.email, customer.reference ] }.compact_blank.map { |value| value.strip.downcase }.uniq
            emails.empty? ? {} : Person.joins(:user).where("LOWER(users.email) IN (?)", emails).includes(:user).group_by { |person| person.user.email.downcase }
          end
        end

        # Every person by the forms of their name: first and last, and the
        # name they go by. A person with no preferred name has the same
        # display name as their legal one (Person fills it in), so both keys
        # are one and they stay exact.
        def people_by_name
          build_name_index
          @people_by_name
        end

        # [key, person id] pairs where the key is the person's legal first
        # and last name only, not the name they go by.
        def legal_only_names
          build_name_index
          @legal_only_names
        end

        def build_name_index
          return if @people_by_name

          @people_by_name = Hash.new { |hash, key| hash[key] = [] }
          @legal_only_names = Set.new
          Person.find_each do |person|
            legal = Accounting::CustomerLinks.comparable_name("#{person.first_name} #{person.last_name}")
            goes_by = Accounting::CustomerLinks.comparable_name(person.display_name)
            [ legal, goes_by ].compact_blank.uniq.each { |key| @people_by_name[key] << person }
            @legal_only_names << [ legal, person.id ] if legal.present? && goes_by.present? && legal != goes_by
          end
        end

        def wards_of(person)
          @wards ||= {}
          @wards[person.id] ||= person.wards.order(:first_name, :last_name).to_a
        end
    end
end
