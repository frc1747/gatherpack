# GatherPack's own ledgers as an accounting source, for a group whose
# ledgers are its books. Each ledger is a customer, linked to the people who
# own it; its entries are charges and payments by sign, applied oldest
# charge first (Accounting::Ledgers::Reader). Nothing is copied into the
# ledgers. Kept current by Accounting::LedgerChanges, with a nightly re-read.
class Gateway::LedgerSource < Gateway
  Gateway.register(self, :accounting)
  include Accounting::Provider

  ENTITY_ROLES = { "Ledger" => :customer, "LedgerTag" => :item, "LedgerEntry" => %i[ charge payment credit ] }.freeze
  CHARGE_SIGNS = %w[ negative positive ].freeze
  DEFAULT_ROLE_LABELS = { "charge" => "Charge", "payment" => "Payment", "credit" => "Credit" }.freeze

  store_accessor :configuration, :ledger_team_ids, :charge_sign, :credit_tag_ids, :new_ledger_team_id, :role_labels
  store_accessor :configuration, :last_change_check_at, :last_full_sync_at, :last_error

  validates :charge_sign, inclusion: { in: CHARGE_SIGNS, message: "is negative or positive" }
  validate :ids_known

  def fields
    [ :ledger_team_ids, :charge_sign, :credit_tag_ids, :new_ledger_team_id ]
  end

  # The tick boxes post arrays.
  def extra_params
    [ { ledger_team_ids: [], credit_tag_ids: [] } ]
  end

  # The settings are stored as ids separated by spaces; the edit form's
  # tick boxes send them as a list.
  %i[ ledger_team_ids credit_tag_ids new_ledger_team_id ].each do |setting|
    define_method(:"#{setting}=") { |value| super(value.is_a?(Array) ? value.compact_blank.join(" ") : value) }
  end

  # Tick boxes and choices on the edit form (GatewayFieldInput).
  def field_input(field)
    case field
    when :ledger_team_ids
      { label: "Which teams' ledgers", as: :check_boxes, choices: team_choices, selected: ledger_teams.map(&:neat_id),
        hint: "Ledgers on the ticked teams are your books. Leave every box empty to use every team's ledgers." }
    when :charge_sign
      { label: "Which entries are charges", as: :select, selected: charge_sign,
        choices: [ [ "Entries below zero are charges; above zero, payments", "negative" ],
                   [ "Entries above zero are charges; below zero, payments", "positive" ] ] }
    when :credit_tag_ids
      { label: "Tags that mean a credit", as: :check_boxes, selected: credit_tags.map(&:neat_id),
        choices: LedgerTag.order(:name).map { |tag| [ tag.name, tag.neat_id ] },
        hint: "A payment carrying one of these tags counts as a credit, such as a scholarship." }
    when :new_ledger_team_id
      { label: "Team for new ledgers", as: :select, choices: team_choices, selected: new_ledger_team&.neat_id, include_blank: "None",
        hint: "Where billing makes a ledger for someone who has none, when the rule has no team of its own." }
    end
  end

  def identifier_icon
    "receipt"
  end

  def source_name
    "Ledgers"
  end

  def charge_sign
    super.presence || "negative"
  end

  def role_label(role)
    (role_labels.presence || {}).fetch(role.to_s, nil).presence || DEFAULT_ROLE_LABELS.fetch(role.to_s)
  end

  # The chosen teams, or none when every team's ledgers count.
  def ledger_teams
    @ledger_teams = nil unless @ledger_teams_for == ledger_team_ids
    @ledger_teams_for = ledger_team_ids
    @ledger_teams ||= find_listed(Team, ledger_team_ids)
  end

  def credit_tags
    find_listed(LedgerTag, credit_tag_ids)
  end

  def new_ledger_team
    find_listed(Team, new_ledger_team_id).first
  end

  # Whether ledgers on the team are this source's customers.
  def covers_team?(team_id)
    ledger_team_ids.blank? || ledger_teams.map(&:id).include?(team_id)
  end

  # The ledgers this source reads.
  def ledgers
    scope = Ledger.all
    ledger_team_ids.present? ? scope.where(team_id: ledger_teams.map(&:id)) : scope
  end

  # Reads one ledger again after it changed: its customer record and
  # entries, or, when it's gone or no longer covered, marks them deleted.
  # The source's page then shows it synced, without an earlier error.
  def sync_ledger(ledger_id)
    started = Time.current
    ledger = Ledger.find_by(id: ledger_id)
    held = accounting_records.where(entity_type: %w[ Ledger LedgerEntry ], customer_external_id: ledger_id)

    saved = if ledger && covers_team?(ledger.team_id)
      Accounting::Sync.new(self).part(reader.rows_for(ledger), held)
    elsif held.current.exists?
      Accounting::Sync.new(self).part([], held)
    else
      []
    end
    record_state!(last_change_check_at: started, last_error: nil)
    saved
  end

  # Queues a LedgerSyncJob for each ledger and each ledger source covering
  # one of team_ids (nil: the teams aren't known, as for a ledger that's gone).
  # Called by Accounting::LedgerChanges after a ledger, entry, tagging or
  # ownership is saved or removed.
  def self.queue_sync(ledger_ids, team_ids)
    return unless Accounting.enabled?

    return if ledger_ids.empty?

    all.each do |source|
      next unless team_ids.nil? || team_ids.any? { |team_id| source.covers_team?(team_id) }

      ledger_ids.each { |ledger_id| Accounting::LedgerSyncJob.perform_later(source, ledger_id) }
    end
  end

  # Queues an OwnerLinksJob for each ledger source, for the ledgers the
  # people own. Called by Accounting::GuardianshipChanges.
  def self.queue_relink(person_ids)
    return unless Accounting.enabled?
    return if person_ids.empty?

    all.each { |source| Accounting::OwnerLinksJob.perform_later(source, person_ids) }
  end

  # Brings the owner links of the ledgers the people own up to date, and
  # queues the rules for those ledgers' owners.
  def relink_owners(person_ids)
    owners = Accounting::Ledgers::OwnerLinks.new(self).reconcile_owned_by(person_ids)
    Accounting::EvaluateRuleJob.for_source(self, owners)
    owners
  end

  def routes
    [ { name: "Records", path: Rails.application.routes.url_helpers.accounting_connection_records_path(self) } ]
  end

  # -- Accounting::Provider --

  def capabilities
    found = Set.new(%i[ deep_links ])
    found << :pay_links if Gateway.any_registered?(:payment)
    found
  end

  def entity_types
    ENTITY_ROLES
  end

  def each_record(entity_type, &block)
    case entity_type
    when "Ledger" then ledgers.includes(:ledger_ownerships).order(:created_at, :id).each { |ledger| yield reader.ledger_row(ledger) }
    when "LedgerTag" then LedgerTag.order(:name, :id).each { |tag| yield reader.tag_row(tag) }
    when "LedgerEntry" then ledgers.order(:created_at, :id).each { |ledger| reader.entry_rows(ledger).each(&block) }
    end
  end

  def normalize(entity_type, data)
    case entity_type
    when "Ledger"
      { role: "customer", customer_external_id: data["id"], name: data["name"], active: true, external_url: data["url"] }
    when "LedgerTag"
      { role: "item", name: data["name"], active: true, external_url: data["url"] }
    when "LedgerEntry"
      normalize_entry(data)
    end
  end

  def external_id(entity_type, data)
    data["id"].to_s
  end

  # Ledger rows carry no version of their own, so the revision is the
  # digest of what was read: a record is saved again only when that changed.
  def revision(entity_type, data)
    content_revision(data)
  end

  def full_sync_cadence
    :nightly
  end

  # Ledger owners are linked to their ledger's customer (Accounting::Ledgers::OwnerLinks).
  def after_sync(records)
    Accounting::Ledgers::OwnerLinks.new(self).after_sync(records)
  end

  private
    def reader
      Accounting::Ledgers::Reader.new(self)
    end

    def team_choices
      Team.order(:name).map { |team| [ team.name, team.neat_id ] }
    end

    def normalize_entry(data)
      role = data["role"]
      total = data["amount_cents"].to_i.abs
      tag_ids = Array(data["tag_ids"])
      columns = {
        role: role,
        customer_external_id: data["ledger_id"],
        txn_date: data["created_at"].present? ? Time.zone.parse(data["created_at"]).to_date : nil,
        total_cents: total,
        lines: [ { "item_id" => tag_ids.first, "class_id" => nil, "amount_cents" => total } ],
        item_ids: tag_ids,
        description: data["remark"].presence,
        external_url: data["url"],
        external_updated_at: nil
      }

      if role == "charge"
        label = [ role_label("charge"), data["first_tag_name"].presence ].compact.join(" · ")
        columns.merge(balance_cents: data["balance_cents"].to_i, pay_url: data["pay_url"], public_label: label)
      else
        unapplied = data["unapplied_cents"].to_i
        columns.merge(applied_to: Array(data["applied_to"]), unapplied_cents: unapplied, public_label: role_label(role),
          balance_cents: (unapplied if role == "credit"))
      end
    end

    # Records named in a setting by id (neat or not), separated by spaces or commas.
    def find_listed(model, text)
      tokens(text).filter_map { |token| find_one(model, token) }
    end

    def find_one(model, token)
      model.find(token)
    rescue ActiveRecord::RecordNotFound, ArgumentError
      nil
    end

    def tokens(text)
      text.to_s.split(/[\s,]+/).compact_blank.uniq
    end

    def ids_known
      { ledger_team_ids: Team, credit_tag_ids: LedgerTag, new_ledger_team_id: Team }.each do |setting, model|
        unknown = tokens(send(setting)).reject { |token| find_one(model, token) }
        errors.add(setting, "has ids that aren't a #{model.model_name.human.downcase}: #{unknown.join(', ')}") if unknown.any?
      end
      errors.add(:new_ledger_team_id, "is one team") if tokens(new_ledger_team_id).size > 1
    end
end
